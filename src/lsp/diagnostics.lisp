(in-package :tycl.lsp)

;;; Diagnostics - Syntax and Type Checking

(defvar *current-type-vars* nil
  "List of type variable names (strings) currently in scope for validation")

(defun check-syntax (text)
  "Check syntax of TyCL code and return diagnostics"
  (let ((diagnostics '())
        (*readtable* tycl/reader:*tycl-readtable*))
    (handler-case
        (with-input-from-string (stream text)
          (loop for form = (read stream nil :eof)
                until (eq form :eof)
                do (validate-form form)))
      (error (e)
        (push (make-diagnostic 0 0 1
                              (format nil "Syntax error: ~A" e)
                              1)
              diagnostics)))
    (nreverse diagnostics)))

(defun validate-form (form)
  "Validate a single form for syntax errors"
  (when (consp form)
    (let ((op (car form)))
      (case op
        ((defun ty-defun)
         (validate-defun-form form))
        ((let let*)
         (validate-let-form form))
        ((defclass)
         (validate-defclass-form form))
        (otherwise
         (when (and (symbolp op) (string= (symbol-name op) "DEFTYPE-TYCL"))
           (validate-deftype-tycl-form form)))))))

(defun validate-defun-form (form)
  "Validate defun form syntax"
  (when (< (length form) 3)
    (error "defun requires at least name and lambda list"))
  (let ((name-part (second form))
        (params-part (third form)))
    (unless (or (symbolp name-part)
               (tycl/annotation:type-annotation-p name-part)
               (and (consp name-part)
                    (symbolp (first name-part))))
      (error "Invalid function name"))
    (unless (listp params-part)
      (error "Invalid parameter list"))))

(defun validate-let-form (form)
  "Validate let form syntax"
  (when (< (length form) 2)
    (error "let requires bindings and body"))
  (let ((bindings (second form)))
    (unless (listp bindings)
      (error "Invalid let bindings"))
    (dolist (binding bindings)
      (unless (or (symbolp binding)
                 (tycl/annotation:type-annotation-p binding)
                 (and (consp binding)
                      (or (symbolp (car binding))
                          (tycl/annotation:type-annotation-p (car binding))
                          (and (consp (car binding))
                               (symbolp (caar binding))))))
        (error "Invalid let binding")))))

(defun validate-defclass-form (form)
  "Validate defclass form syntax"
  (when (< (length form) 3)
    (error "defclass requires at least name, superclasses, and slots")))

(defun check-types (text uri)
  "Check type consistency and return diagnostics.
   Delegates to tycl/type-checker:check-string for actual checking."
  (declare (ignore uri))
  (let ((diagnostics '()))
    (handler-case
        (progn
          (tycl/type-checker:check-string text)
          ;; Convert type-check-errors to LSP diagnostics
          (dolist (err (reverse tycl/type-checker:*type-check-errors*))
            (push (make-diagnostic 0 0 1
                                   (tycl/type-checker:error-message err)
                                   2)  ; severity=Warning
                  diagnostics)))
      (error (e)
        (when *debug-mode*
          (format *error-output* "~%Type checking error: ~A~%" e))))
    diagnostics))

(defun check-form-types (form uri diagnostics)
  "Check types in a form and collect diagnostics"
  (when (consp form)
    (let ((op (car form)))
      (case op
        ((defun ty-defun)
         (check-defun-types form uri diagnostics))
        ((let let*)
         (check-let-types form uri diagnostics))))))

(defun check-defun-types (form uri diagnostics)
  "Check type annotations in defun"
  (let ((name-part (second form))
        (params-part (third form)))
    ;; Check function name type
    (when (consp name-part)
      (let ((type-spec (second name-part)))
        (unless (valid-type-p type-spec)
          (push (make-diagnostic-for-symbol
                 name-part
                 (format nil "Invalid type annotation: ~A" type-spec)
                 1)
                diagnostics))))
    ;; Check parameter types
    (when (consp params-part)
      (dolist (param params-part)
        (when (consp param)
          (let ((type-spec (second param)))
            (unless (valid-type-p type-spec)
              (push (make-diagnostic-for-symbol
                     param
                     (format nil "Invalid type annotation: ~A" type-spec)
                     1)
                    diagnostics))))))))

(defun check-let-types (form uri diagnostics)
  "Check type annotations in let"
  (declare (ignore uri))
  (let ((bindings (second form)))
    (when (consp bindings)
      (dolist (binding bindings)
        (when (and (consp binding)
                  (consp (car binding)))
          (let ((type-spec (second (car binding))))
            (unless (valid-type-p type-spec)
              (push (make-diagnostic-for-symbol
                     binding
                     (format nil "Invalid type annotation: ~A" type-spec)
                     1)
                    diagnostics))))))))

(defun validate-deftype-tycl-form (form)
  "Validate deftype-tycl form syntax"
  (when (< (length form) 3)
    (error "deftype-tycl requires name and type"))
  (let ((name-spec (second form)))
    (cond
      ;; Parametric: (deftype-tycl (result T) (:list (T)))
      ((consp name-spec)
       (unless (and (symbolp (car name-spec))
                    (not (keywordp (car name-spec)))
                    (every #'symbolp (cdr name-spec)))
         (error "deftype-tycl parameterized form must be (name param...)")))
      ;; Simple: (deftype-tycl userid :integer)
      (t
       (unless (and (symbolp name-spec) (not (keywordp name-spec)))
         (error "deftype-tycl name must be a non-keyword symbol"))))))

(defun valid-type-p (type-spec)
  "Check if a type specification is valid"
  (cond
    ((keywordp type-spec)
     (member type-spec tycl::*valid-types*))
    ;; Non-keyword symbol: check if it's a type variable, type alias, or class
    ((symbolp type-spec)
     (let ((name (string-upcase (symbol-name type-spec))))
       (or (member name *current-type-vars* :test #'string=)
           (not (null (tycl:lookup-type-alias
                       tycl:*current-package*
                       name))))))
    ((consp type-spec)
     (if (keywordp (car type-spec))
         ;; Generic type like (:list (:integer))
         (and (member (car type-spec) tycl::*valid-types*)
              (every #'valid-type-p (cdr type-spec)))
         ;; Union type or parametric alias application
         (let* ((head (car type-spec))
                (alias-name (when (symbolp head) (string-upcase (symbol-name head))))
                (alias-expanded (when alias-name
                                  (tycl:lookup-type-alias tycl:*current-package* alias-name))))
           (if alias-expanded
               ;; Parametric type application: check that args are valid
               (every #'valid-type-p (cdr type-spec))
               ;; Union type
               (every #'valid-type-p type-spec)))))
    (t nil)))

(defun make-diagnostic (line start-char end-char message severity)
  "Create a diagnostic object
  severity: 1=Error, 2=Warning, 3=Information, 4=Hint"
  `((:range . ((:start . ((:line . ,line) (:character . ,start-char)))
               (:end . ((:line . ,line) (:character . ,end-char)))))
    (:severity . ,severity)
    (:message . ,message)
    (:source . "tycl")))

(defun make-diagnostic-for-symbol (symbol message severity)
  "Create a diagnostic for a symbol (simplified - uses line 0)"
  (declare (ignore symbol))
  (make-diagnostic 0 0 1 message severity))

(defun publish-diagnostics (uri text stream)
  "Analyze text and publish diagnostics"
  (let ((syntax-diagnostics (check-syntax text))
        (type-diagnostics (check-types text uri)))
    (let ((all-diagnostics (append syntax-diagnostics type-diagnostics)))
      (send-notification
       "textDocument/publishDiagnostics"
       `((:uri . ,uri)
         (:diagnostics . ,(if all-diagnostics
                             (coerce all-diagnostics 'vector)
                             #())))
       stream))))
