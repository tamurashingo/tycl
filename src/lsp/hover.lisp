(in-package :tycl.lsp)

;;; Hover - Type Information Display

(defun extract-symbol-at-position (text line character)
  "Extract symbol name at the given position"
  (let* ((lines (split-string text #\Newline))
         (target-line (if (< line (length lines))
                         (nth line lines)
                         "")))
    (when (< character (length target-line))
      (let* ((start (or (position-if-not #'symbol-char-p target-line
                                        :end character
                                        :from-end t)
                       -1))
             (end (or (position-if-not #'symbol-char-p target-line
                                      :start character)
                     (length target-line))))
        (when (< (1+ start) end)
          (string-upcase (subseq target-line (1+ start) end)))))))

(defun symbol-char-p (char)
  "Check if character is valid in a symbol name"
  (or (alphanumericp char)
      (find char "-_*+/<>=!?&")))

(defun split-string (string delimiter)
  "Split string by delimiter"
  (loop with start = 0
        for pos = (position delimiter string :start start)
        collect (subseq string start (or pos (length string)))
        while pos
        do (setf start (1+ pos))))

(defun format-type-spec (type-spec)
  "Format type specification for display"
  (cond
    ((keywordp type-spec)
     (format nil "~(~A~)" type-spec))
    ((consp type-spec)
     (cond
       ;; Union type: all elements are keywords, e.g. (:integer :null)
       ((every #'keywordp type-spec)
        (format nil "~{~A~^ | ~}"
               (mapcar #'format-type-spec type-spec)))
       ;; Generic type: first is keyword, rest are params, e.g. (:list (:integer))
       ((keywordp (car type-spec))
        (format nil "~(~A~)<~{~A~^, ~}>"
               (car type-spec)
               (mapcar #'format-type-spec (cdr type-spec))))
       ;; Fallback: union of mixed types
       (t
        (format nil "~{~A~^ | ~}"
               (mapcar #'format-type-spec type-spec)))))
    (t (format nil "~A" type-spec))))

(defun format-function-signature (info)
  "Format function type signature for hover display"
  (let ((type-spec (type-info-type-spec info)))
    (if (and (consp type-spec)
            (eq (car type-spec) :function))
        (let ((params (second type-spec))
              (return-type (third type-spec)))
          (format nil "```commonlisp~%(defun ~A (~{~A~^ ~})~%  => ~A)~%```"
                 (type-info-name info)
                 (mapcar (lambda (param)
                          (format nil "[~A ~A]"
                                  (getf param :name)
                                  (format-type-spec (getf param :type))))
                        params)
                 (format-type-spec return-type)))
        (format nil "```commonlisp~%(defun ~A ...)~%```"
               (type-info-name info)))))

(defun format-value-info (info)
  "Format value type information for hover display"
  (format nil "```commonlisp~%(defvar ~A ~A)~%```"
         (type-info-name info)
         (format-type-spec (type-info-type-spec info))))

(defun format-class-info (info)
  "Format class information for hover display"
  (format nil "```commonlisp~%(defclass ~A ...)~%```"
         (type-info-name info)))

(defun format-type-alias-info (info)
  "Format type alias information for hover display"
  (format nil "```commonlisp~%(deftype-tycl ~A ~A)~%```"
          (type-info-name info)
          (format-type-spec (type-info-type-spec info))))

(defun format-hover-content (info)
  "Format type information for hover display"
  (case (type-info-kind info)
    (:function (format-function-signature info))
    (:value (format-value-info info))
    (:class (format-class-info info))
    (:method (format-function-signature info))
    (:type-alias (format-type-alias-info info))
    (otherwise (format nil "Symbol: ~A" (type-info-name info)))))

(defun extract-package-name (text)
  "Extract package name from file content"
  (let ((lines (split-string text #\Newline)))
    (loop for line in lines
          do (let ((trimmed (string-trim '(#\Space #\Tab) line)))
               (when (and (> (length trimmed) 0)
                          (char= (char trimmed 0) #\()))
                 (let ((forms (ignore-errors (read-from-string trimmed))))
                   (when (and (consp forms)
                              (eq (car forms) 'in-package))
                     (let ((package-spec (second forms)))
                       (return (string-upcase
                                 (if (keywordp package-spec)
                                     (symbol-name package-spec)
                                     (if (and (consp package-spec)
                                              (eq (car package-spec) 'quote))
                                         (symbol-name (second package-spec))
                                         (format nil "~A" package-spec))))))))))))

(defun get-file-specific-types-file (uri)
  "Get the .tycl-types file corresponding to the given .tycl file URI"
  (let* ((file-path (ppcre:regex-replace "^file://" uri ""))
         (parsed-path (uiop:parse-native-namestring file-path)))
    (when (string= (pathname-type parsed-path) "tycl")
      (make-pathname :type "tycl-types" :defaults parsed-path))))

(defun query-type-info-with-file-priority (symbol-name package-name uri)
  "Query type information with preference for file-specific types"
  (when *debug-mode*
    (format *error-output* "~%[Hover] Querying symbol: ~A, package: ~A~%"
            symbol-name package-name))

  ;; First, try the specific package
  (let ((info (when package-name (query-type-info symbol-name package-name))))
    (when info
      (when *debug-mode*
        (format *error-output* "~%[Hover] Found in package ~A~%" package-name))
      (return-from query-type-info-with-file-priority info)))

  ;; If not found and we have a URI, check if there's a file-specific types file
  (when uri
    (let ((types-file (get-file-specific-types-file uri)))
      (when (and types-file (probe-file types-file))
        (when *debug-mode*
          (format *error-output* "~%[Hover] Checking file-specific types: ~A~%" types-file))
        ;; Try to find in the file-specific package first
        (let ((info (query-type-info symbol-name package-name)))
          (when info
            (when *debug-mode*
              (format *error-output* "~%[Hover] Found in file-specific package~%"))
            (return-from query-type-info-with-file-priority info))))))

  ;; Fallback to global search
  (when *debug-mode*
    (format *error-output* "~%[Hover] Falling back to global search~%"))
  (let ((info (query-type-info symbol-name)))
    (when *debug-mode*
      (if info
          (format *error-output* "~%[Hover] Found globally: ~A~%"
                  (type-info-name info))
          (format *error-output* "~%[Hover] Not found anywhere~%")))
    info))

(defun get-hover-info (uri line character)
  "Get hover information for position in document"
  (let* ((text (gethash uri *open-documents*))
         (symbol-name (and text (extract-symbol-at-position text line character))))
    (when *debug-mode*
      (format *error-output* "~%[Hover] Request: URI=~A, line=~A, char=~A~%"
              uri line character)
      (format *error-output* "~%[Hover] Extracted symbol: ~A~%" symbol-name))

    (when symbol-name
      (let* ((package-name (and text (extract-package-name text)))
             (info (query-type-info-with-file-priority symbol-name package-name uri)))

        (when *debug-mode*
          (format *error-output* "~%[Hover] Package: ~A~%" package-name)
          (format *error-output* "~%[Hover] Info found: ~A~%" (not (null info))))

        (when info
          `((:contents . ((:kind . "markdown")
                         (:value . ,(format-hover-content info))))
            (:range . ((:start . ((:line . ,line) (:character . 0)))
                       (:end . ((:line . ,line) (:character . 100)))))))))))
