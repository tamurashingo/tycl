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
                       (uiop:getcwd))))
    (when *debug-mode*
      (format *error-output* "~%Initializing workspace: ~A~%" root-path))
    
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

(defun handle-did-change (params stream)
  "Handle textDocument/didChange notification"
  (let* ((text-document (cdr (assoc :text-document params)))
         (uri (cdr (assoc :uri text-document)))
         (content-changes (cdr (assoc :content-changes params))))
    ;; For full document sync (change = 1) or incremental (change = 2)
    ;; We use incremental but for simplicity, take the last full text
    (when content-changes
      (let ((new-text (cdr (assoc :text (car (last content-changes))))))
        (when new-text
          (setf (gethash uri *open-documents*) new-text)
          ;; Send diagnostics on change
          (publish-diagnostics uri new-text stream))))
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
    
    ;; If it's a .tycl file, reload its type information
    (when (string= (pathname-type path) "tycl")
      (let ((types-file (make-pathname :type "tycl-types" :defaults path)))
        (when (probe-file types-file)
          (handler-case
              (load-type-info-file types-file)
            (error (e)
              (when *debug-mode*
                (format *error-output* "~%Error reloading types: ~A~%" e)))))))
    
    ;; Send diagnostics
    (when text
      (publish-diagnostics uri text stream))))

(defun handle-did-close (params stream)
  "Handle textDocument/didClose notification"
  (declare (ignore stream))
  (let* ((text-document (cdr (assoc :text-document params)))
         (uri (cdr (assoc :uri text-document))))
    (remhash uri *open-documents*)
    (when *debug-mode*
      (format *error-output* "~%Closed document: ~A~%" uri))))

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
