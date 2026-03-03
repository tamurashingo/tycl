(in-package :tycl.lsp)

;;; LSP Method Handlers

(defvar *open-documents* (make-hash-table :test 'equal)
  "Cache of open document contents. Key: URI, Value: document text")

(defun handle-initialize (params id stream)
  "Handle initialize request"
  (let* ((root-uri (cdr (assoc :root-uri params)))
         (root-path (if root-uri
                       (uiop:parse-native-namestring
                        (ppcre:regex-replace "^file://" root-uri ""))
                       (uiop:getcwd)))
         (init-options (cdr (assoc :initialization-options params)))
         (debounce-ms (when init-options
                        (cdr (assoc :diagnostic-debounce-ms init-options)))))
    (when debounce-ms
      (setf *diagnostics-debounce-ms* debounce-ms))
    (when *debug-mode*
      (format *error-output* "~%Initializing workspace: ~A~%" root-path)
      (format *error-output* "~%Diagnostics debounce: ~Ams~%" *diagnostics-debounce-ms*))

    ;; Load and cache .asd files from workspace root
    (handler-case
        (load-and-cache-asd-files root-path)
      (error (e)
        (when *debug-mode*
          (format *error-output* "~%Error loading .asd files: ~A~%" e))))

    ;; Transpile all .tycl files to generate tycl-types.tmp
    (when *cached-asd-files*
      (dolist (asd-file *cached-asd-files*)
        (handler-case
            (progn
              (when *debug-mode*
                (format *error-output* "~%Transpiling all in ~A~%" asd-file))
              (transpile-all-in-asd asd-file :output *error-output*))
          (error (e)
            (when *debug-mode*
              (format *error-output* "~%Error transpiling ~A: ~A~%" asd-file e))))))

    ;; Load type information from workspace
    (load-workspace-types root-path)
    
    (send-response
     id
     `((:capabilities
        . ((:text-document-sync
            . ((:open-close . t)
               (:change . 2)
               (:save . t)))
           (:hover-provider . t)
           (:completion-provider
            . ((:resolve-provider . :json-false)
               (:trigger-characters . #("(" "[" " "))))
           (:definition-provider . t)
           (:document-symbol-provider . t)))
       (:server-info
        . ((:name . "TyCL LSP Server")
           (:version . "0.1.0"))))
     stream)))

(defun handle-initialized (params stream)
  "Handle initialized notification"
  (declare (ignore params stream))
  (when *debug-mode*
    (format *error-output* "~%Client initialized~%")))

(defun handle-shutdown (id stream)
  "Handle shutdown request"
  (setf *shutdown-requested* t)
  (send-response id :null stream))

(defun handle-exit ()
  "Handle exit notification"
  (uiop:quit (if *shutdown-requested* 0 1)))

(defun uri-to-path (uri)
  "Convert file:// URI to filesystem path"
  (uiop:parse-native-namestring
   (ppcre:regex-replace "^file://" uri "")))

(defun handle-did-open (params stream)
  "Handle textDocument/didOpen notification"
  (declare (ignore stream))
  (let* ((text-document (cdr (assoc :text-document params)))
         (uri (cdr (assoc :uri text-document)))
         (text (cdr (assoc :text text-document))))
    (setf (gethash uri *open-documents*) text)
    (when *debug-mode*
      (format *error-output* "~%Opened document: ~A~%" uri))))

(defun position-to-offset (text line character)
  "Convert LSP line/character position to a string offset.
   LINE and CHARACTER are 0-based."
  (let ((offset 0)
        (current-line 0))
    (loop for i from 0 below (length text)
          do (when (= current-line line)
               (return-from position-to-offset (+ offset character)))
             (if (char= (char text i) #\Newline)
                 (incf current-line)
                 nil)
             (incf offset))
    ;; If we reach here, the position is at or past the last line
    (+ offset character)))

(defun apply-content-change (text change)
  "Apply a single content change to TEXT.
   If CHANGE has :range, apply incrementally. Otherwise treat as full replacement."
  (let ((range (cdr (assoc :range change)))
        (new-text (cdr (assoc :text change))))
    (if range
        ;; Incremental change: apply range-based replacement
        (let* ((start (cdr (assoc :start range)))
               (end (cdr (assoc :end range)))
               (start-line (cdr (assoc :line start)))
               (start-char (cdr (assoc :character start)))
               (end-line (cdr (assoc :line end)))
               (end-char (cdr (assoc :character end)))
               (start-offset (position-to-offset text start-line start-char))
               (end-offset (position-to-offset text end-line end-char)))
          (concatenate 'string
                       (subseq text 0 start-offset)
                       new-text
                       (subseq text end-offset)))
        ;; Full replacement
        new-text)))

(defun handle-did-change (params stream)
  "Handle textDocument/didChange notification"
  (let* ((text-document (cdr (assoc :text-document params)))
         (uri (cdr (assoc :uri text-document)))
         (content-changes (cdr (assoc :content-changes params))))
    (when content-changes
      (let ((text (gethash uri *open-documents*)))
        ;; Apply each content change sequentially
        (dolist (change content-changes)
          (setf text (apply-content-change text change)))
        (setf (gethash uri *open-documents*) text)
        ;; Schedule diagnostics with debounce (or immediate if debounce is 0)
        (if (zerop *diagnostics-debounce-ms*)
            (publish-diagnostics uri text stream)
            (schedule-diagnostics uri))))
    (when *debug-mode*
      (format *error-output* "~%Changed document: ~A~%" uri))))

(defun handle-did-save (params stream)
  "Handle textDocument/didSave notification"
  (let* ((text-document (cdr (assoc :text-document params)))
         (uri (cdr (assoc :uri text-document)))
         (path (uri-to-path uri))
         (text (gethash uri *open-documents*)))
    (when *debug-mode*
      (format *error-output* "~%Saved document: ~A~%" uri))

    ;; Cancel any pending debounced diagnostics for this URI
    (remhash uri *pending-diagnostics*)

    ;; If it's a .tycl file, transpile and reload type information
    (when (string= (pathname-type path) "tycl")
      ;; Transpile the file to generate .lisp and .tycl-types
      (let ((types-file (transpile-tycl-file path)))
        ;; Load the generated (or existing) .tycl-types
        (when types-file
          (handler-case
              (load-type-info-file types-file)
            (error (e)
              (when *debug-mode*
                (format *error-output* "~%Error reloading types: ~A~%" e)))))))

    ;; Send diagnostics immediately on save
    (when text
      (publish-diagnostics uri text stream))))

(defun handle-did-close (params stream)
  "Handle textDocument/didClose notification"
  (declare (ignore stream))
  (let* ((text-document (cdr (assoc :text-document params)))
         (uri (cdr (assoc :uri text-document))))
    (remhash uri *open-documents*)
    ;; Cancel any pending debounced diagnostics for this URI
    (remhash uri *pending-diagnostics*)
    (when *debug-mode*
      (format *error-output* "~%Closed document: ~A~%" uri))))

;;; Diagnostics debounce helpers

(defun schedule-diagnostics (uri)
  "Schedule diagnostics for URI after debounce delay.
   Sets the deadline in *pending-diagnostics*."
  (let ((deadline (+ (get-internal-real-time)
                     (* *diagnostics-debounce-ms*
                        (/ internal-time-units-per-second 1000)))))
    (setf (gethash uri *pending-diagnostics*) deadline)))

(defun process-pending-diagnostics (stream)
  "Process any pending diagnostics whose deadline has passed.
   Publishes diagnostics for each expired URI and removes it from the pending table."
  (let ((now (get-internal-real-time))
        (expired-uris nil))
    ;; Collect expired URIs
    (maphash (lambda (uri deadline)
               (when (<= deadline now)
                 (push uri expired-uris)))
             *pending-diagnostics*)
    ;; Process each expired URI
    (dolist (uri expired-uris)
      (remhash uri *pending-diagnostics*)
      (let ((text (gethash uri *open-documents*)))
        (when text
          (publish-diagnostics uri text stream))))))

(defun nearest-deadline ()
  "Return the nearest deadline from *pending-diagnostics*, or NIL if none pending."
  (let ((min-deadline nil))
    (maphash (lambda (uri deadline)
               (declare (ignore uri))
               (when (or (null min-deadline) (< deadline min-deadline))
                 (setf min-deadline deadline)))
             *pending-diagnostics*)
    min-deadline))

(defun compute-timeout-ms ()
  "Compute milliseconds until the nearest deadline, or NIL if no pending diagnostics.
   Returns 0 if the deadline has already passed."
  (let ((deadline (nearest-deadline)))
    (when deadline
      (let ((remaining (- deadline (get-internal-real-time))))
        (max 0 (ceiling (* remaining (/ 1000 internal-time-units-per-second))))))))

(defun handle-hover (params id stream)
  "Handle textDocument/hover request"
  (let* ((text-document (cdr (assoc :text-document params)))
         (uri (cdr (assoc :uri text-document)))
         (position (cdr (assoc :position params)))
         (line (cdr (assoc :line position)))
         (character (cdr (assoc :character position))))
    
    (let ((hover-info (get-hover-info uri line character)))
      (if hover-info
          (send-response id hover-info stream)
          (send-response id :null stream)))))

(defun handle-completion (params id stream)
  "Handle textDocument/completion request"
  (let* ((text-document (cdr (assoc :text-document params)))
         (uri (cdr (assoc :uri text-document)))
         (position (cdr (assoc :position params)))
         (line (cdr (assoc :line position)))
         (character (cdr (assoc :character position))))
    
    (let ((items (get-completion-items uri line character)))
      (send-response id
                    (if items
                        (coerce items 'vector)
                        #())
                    stream))))

(defun handle-completion-resolve (params id stream)
  "Handle completionItem/resolve request"
  ;; For now, just return the item as-is since we don't have additional
  ;; information to resolve. This prevents the "Method not found" error.
  (send-response id params stream))

(defun handle-definition (params id stream)
  "Handle textDocument/definition request"
  (declare (ignore params))
  ;; TODO: Implement go-to-definition
  ;; For now, return null
  (send-response id :null stream))

(defun handle-document-symbol (params id stream)
  "Handle textDocument/documentSymbol request"
  (declare (ignore params))
  ;; TODO: Implement document symbols
  ;; For now, return empty list
  (send-response id #() stream))
