;;;; lsp-integration.lisp
;;;; LSP (Language Server Protocol) integration for TyCL

(in-package :tycl)

;;; ============================================================
;;; JSON Serialization
;;; ============================================================

(defun type-to-json (type-spec)
  "Convert a type specification to JSON-compatible structure"
  (cond
    ;; Simple type (keyword)
    ((keywordp type-spec)
     (string-downcase (symbol-name type-spec)))
    
    ;; Union type (:integer :string)
    ((and (listp type-spec)
          (every #'keywordp type-spec))
     `((:type . "union")
       (:types . ,(mapcar (lambda (typ) (string-downcase (symbol-name typ))) type-spec))))
    
    ;; Generic type (:list (:integer))
    ((and (listp type-spec)
          (keywordp (first type-spec)))
     (let ((base (first type-spec))
           (params (rest type-spec)))
       `((:type . "generic")
         (:base . ,(string-downcase (symbol-name base)))
         (:params . ,(mapcar #'type-to-json params)))))
    
    ;; User-defined type (symbol)
    ((symbolp type-spec)
     (string-downcase (symbol-name type-spec)))
    
    ;; Unknown
    (t
     "any")))

(defun type-info-to-json (type-info)
  "Convert type-info object to JSON-compatible structure"
  (let ((base-info `((:kind . ,(string-downcase (symbol-name (type-info-kind type-info))))
                     (:package . ,(type-info-package type-info))
                     (:symbol . ,(type-info-symbol type-info)))))
    (ecase (type-info-kind type-info)
      (:value
       (append base-info
               `((:type . ,(type-to-json (value-type-spec type-info))))))
      
      (:function
       (append base-info
               `((:params . ,(mapcar (lambda (param)
                                      `((:name . ,(getf param :name))
                                        (:type . ,(type-to-json (getf param :type)))))
                                    (function-params type-info)))
                 (:return . ,(type-to-json (function-return-type type-info))))))
      
      (:method
       (append base-info
               `((:params . ,(mapcar (lambda (param)
                                      `((:name . ,(getf param :name))
                                        (:type . ,(type-to-json (getf param :type)))
                                        ,@(when (getf param :specializer)
                                            `((:specializer . ,(string-downcase 
                                                               (symbol-name (getf param :specializer))))))))
                                    (function-params type-info)))
                 (:return . ,(type-to-json (function-return-type type-info))))))
      
      (:class
       (append base-info
               `((:slots . ,(mapcar (lambda (slot)
                                     `((:name . ,(getf slot :name))
                                       (:type . ,(type-to-json (getf slot :type)))))
                                   (class-slots type-info)))
                 (:superclasses . ,(mapcar (lambda (s) (string-downcase (symbol-name s)))
                                          (class-superclasses type-info)))))))))

(defun serialize-type-database-json ()
  "Serialize current type database to JSON-compatible structure"
  (let ((entries '()))
    (maphash (lambda (key type-info)
               (declare (ignore key))
               (push (type-info-to-json type-info) entries))
             (db-entries *type-database*))
    `((:version . 1)
      (:timestamp . ,(get-universal-time))
      (:entries . ,(nreverse entries)))))

(defun save-type-database-json (output-file)
  "Save type database to JSON file"
  (let ((json-data (serialize-type-database-json)))
    (with-open-file (out output-file
                         :direction :output
                         :if-exists :supersede
                         :if-does-not-exist :create)
      (write-json json-data out))))

(defun write-json (data stream &optional (indent 0))
  "Write JSON data to stream with indentation"
  (cond
    ;; Null
    ((null data)
     (write-string "null" stream))
    
    ;; String
    ((stringp data)
     (write-char #\" stream)
     (write-string (escape-json-string data) stream)
     (write-char #\" stream))
    
    ;; Number
    ((numberp data)
     (format stream "~a" data))
    
    ;; Boolean
    ((eq data t)
     (write-string "true" stream))
    ((eq data :true)
     (write-string "true" stream))
    ((eq data :false)
     (write-string "false" stream))
    
    ;; Association list (object)
    ((and (listp data)
          (every (lambda (x) (and (consp x) (not (listp (car x))))) data))
     (write-char #\{ stream)
     (when data
       (format stream "~%")
       (let ((first t))
         (dolist (pair data)
           (unless first
             (write-char #\, stream)
             (format stream "~%"))
           (setf first nil)
           (dotimes (i (+ indent 2))
             (write-char #\Space stream))
           (write-char #\" stream)
           (write-string (escape-json-string (format nil "~a" (car pair))) stream)
           (write-char #\" stream)
           (write-string ": " stream)
           (write-json (cdr pair) stream (+ indent 2))))
       (format stream "~%")
       (dotimes (i indent)
         (write-char #\Space stream)))
     (write-char #\} stream))
    
    ;; Regular list (array)
    ((listp data)
     (write-char #\[ stream)
     (when data
       (let ((first t))
         (dolist (item data)
           (unless first
             (write-string ", " stream))
           (setf first nil)
           (write-json item stream (+ indent 2)))))
     (write-char #\] stream))
    
    ;; Default: convert to string
    (t
     (write-char #\" stream)
     (write-string (escape-json-string (format nil "~a" data)) stream)
     (write-char #\" stream))))

(defun escape-json-string (str)
  "Escape special characters in JSON string"
  (with-output-to-string (out)
    (loop for char across str
          do (case char
               (#\" (write-string "\\\"" out))
               (#\\ (write-string "\\\\" out))
               (#\Newline (write-string "\\n" out))
               (#\Return (write-string "\\r" out))
               (#\Tab (write-string "\\t" out))
               (otherwise (write-char char out))))))

;;; ============================================================
;;; Query API
;;; ============================================================

(defun get-symbol-type (symbol &optional package)
  "Get type information for a symbol"
  (if package
      (lookup-type-info package symbol)
      (gethash (string-upcase symbol) (db-entries *type-database*))))

(defun get-package-symbols (package)
  "Get all symbols defined in a package"
  (let ((symbols '()))
    (maphash (lambda (key type-info)
               (when (string-equal package (type-info-package type-info))
                 (push (type-info-symbol type-info) symbols)))
             (db-entries *type-database*))
    (nreverse symbols)))

(defun find-functions-by-return-type (return-type)
  "Find all functions that return the specified type"
  (let ((functions '()))
    (maphash (lambda (key type-info)
               (when (and (eq (type-info-kind type-info) :function)
                          (type-equal (function-return-type type-info) return-type))
                 (push (cons key type-info) functions)))
             (db-entries *type-database*))
    (nreverse functions)))

(defun find-functions-with-param-type (param-type)
  "Find all functions that accept the specified type as parameter"
  (let ((functions '()))
    (maphash (lambda (key type-info)
               (when (eq (type-info-kind type-info) :function)
                 (let ((params (function-params type-info)))
                   (when (some (lambda (param)
                                (type-equal (getf param :type) param-type))
                              params)
                     (push (cons key type-info) functions)))))
             (db-entries *type-database*))
    (nreverse functions)))

(defun get-class-hierarchy (class-name &optional package)
  "Get the inheritance hierarchy for a class"
  (let ((info (get-symbol-type class-name package)))
    (when (and info (eq (type-info-kind info) :class))
      (let ((superclasses (class-superclasses info))
            (subclasses '()))
        ;; Find subclasses
        (maphash (lambda (key type-info)
                   (declare (ignore key))
                   (when (and (eq (type-info-kind type-info) :class)
                              (member (intern (string-upcase class-name))
                                     (class-superclasses type-info)
                                     :test #'string-equal))
                     (push (type-info-symbol type-info) subclasses)))
                 (db-entries *type-database*))
        (list :class class-name
              :superclasses superclasses
              :subclasses (nreverse subclasses))))))

(defun get-methods-for-class (class-name)
  "Get all methods defined for a class"
  (let ((methods '()))
    (maphash (lambda (key type-info)
               (when (eq (type-info-kind type-info) :method)
                 (let ((params (function-params type-info)))
                   (when (some (lambda (param)
                                (let ((spec (getf param :specializer)))
                                  (and spec
                                       (string-equal class-name (symbol-name spec)))))
                              params)
                     (push (cons key type-info) methods)))))
             (db-entries *type-database*))
    (nreverse methods)))

(defun type-equal (type1 type2)
  "Check if two type specifications are equal"
  (cond
    ((and (keywordp type1) (keywordp type2))
     (eq type1 type2))
    ((and (symbolp type1) (symbolp type2))
     (eq type1 type2))
    ((and (listp type1) (listp type2))
     (and (= (length type1) (length type2))
          (every #'type-equal type1 type2)))
    (t nil)))

;;; ============================================================
;;; LSP Server Integration
;;; ============================================================

(defun get-completion-items (prefix &optional package)
  "Get completion items for LSP completion request"
  (let ((items '()))
    (maphash (lambda (key type-info)
               (when (and (or (null package)
                             (string-equal package (type-info-package type-info)))
                          (search (string-upcase prefix) 
                                 (string-upcase (type-info-symbol type-info))))
                 (push (make-completion-item type-info) items)))
             (db-entries *type-database*))
    (nreverse items)))

(defun make-completion-item (type-info)
  "Create LSP completion item from type-info"
  (let ((kind (ecase (type-info-kind type-info)
                (:function "Function")
                (:method "Method")
                (:class "Class")
                (:value "Variable"))))
    `((:label . ,(type-info-symbol type-info))
      (:kind . ,kind)
      (:detail . ,(format-type-signature type-info))
      (:documentation . ""))))

(defun format-type-signature (type-info)
  "Format type signature for display"
  (ecase (type-info-kind type-info)
    (:value
     (format nil "~a" (value-type-spec type-info)))
    
    (:function
     (format nil "(~{~a~^ ~}) → ~a"
             (mapcar (lambda (p) (getf p :type)) 
                    (function-params type-info))
             (function-return-type type-info)))
    
    (:method
     (format nil "(~{~a~^ ~}) → ~a"
             (mapcar (lambda (p) (getf p :type)) 
                    (function-params type-info))
             (function-return-type type-info)))
    
    (:class
     (format nil "class ~a" (type-info-symbol type-info)))))

(defun get-hover-info (symbol &optional package)
  "Get hover information for LSP hover request"
  (let ((type-info (get-symbol-type symbol package)))
    (when type-info
      `((:contents . ,(format-hover-contents type-info))))))

(defun format-hover-contents (type-info)
  "Format hover contents for display"
  (with-output-to-string (s)
    (format s "**~a** ~a~%" 
            (type-info-kind type-info)
            (type-info-symbol type-info))
    (format s "Package: `~a`~%~%" (type-info-package type-info))
    
    (ecase (type-info-kind type-info)
      (:value
       (format s "Type: `~a`" (value-type-spec type-info)))
      
      (:function
       (format s "```lisp~%")
       (format s "(defun ~a (~{~a~^ ~})~%" 
               (type-info-symbol type-info)
               (mapcar (lambda (p) (getf p :name))
                      (function-params type-info)))
       (format s "  ;; Returns: ~a~%" (function-return-type type-info))
       (format s "  ...)~%```"))
      
      (:method
       (format s "```lisp~%")
       (format s "(defmethod ~a (~{~a~^ ~})~%" 
               (type-info-symbol type-info)
               (mapcar (lambda (p) 
                        (if (getf p :specializer)
                            (format nil "(~a ~a)" (getf p :name) (getf p :specializer))
                            (getf p :name)))
                      (function-params type-info)))
       (format s "  ;; Returns: ~a~%" (function-return-type type-info))
       (format s "  ...)~%```"))
      
      (:class
       (format s "```lisp~%")
       (format s "(defclass ~a (~{~a~^ ~})~%" 
               (type-info-symbol type-info)
               (class-superclasses type-info))
       (format s "  (~{~a~^~%   ~}))~%```"
               (mapcar (lambda (slot)
                        (format nil "(~a :type ~a)" 
                               (getf slot :name)
                               (getf slot :type)))
                      (class-slots type-info)))))))

;;; ============================================================
;;; Diagnostic Support
;;; ============================================================

(defun check-file-diagnostics (file)
  "Check file for type errors and return LSP diagnostics"
  (let ((diagnostics '())
        (*current-package* "COMMON-LISP-USER"))
    (handler-case
        (with-open-file (in file)
          (loop for form = (read in nil :eof)
                for line-no from 1
                until (eq form :eof)
                do (handler-case
                       (progn
                         (extract-type-from-form form)
                         (check-form-types form))
                     (error (e)
                       (push `((:line . ,line-no)
                              (:severity . "error")
                              (:message . ,(format nil "~a" e)))
                             diagnostics)))))
      (error (e)
        (push `((:line . 1)
               (:severity . "error")
               (:message . ,(format nil "File error: ~a" e)))
              diagnostics)))
    (nreverse diagnostics)))

(defun check-form-types (form)
  "Check types in a form (placeholder for future implementation)"
  ;; This will be expanded with actual type checking logic
  (declare (ignore form))
  t)
