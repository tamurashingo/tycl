(in-package :tycl.lsp)

;;; Diagnostics - Syntax and Type Checking

(defun check-syntax (text)
  "Check syntax of TyCL code and return diagnostics"
  (let ((diagnostics '()))
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
         (validate-defclass-form form))))))

(defun validate-defun-form (form)
  "Validate defun form syntax"
  (when (< (length form) 3)
    (error "defun requires at least name and lambda list"))
  (let ((name-part (second form))
        (params-part (third form)))
    (unless (or (symbolp name-part)
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
                 (and (consp binding)
                      (or (symbolp (car binding))
                          (and (consp (car binding))
                               (symbolp (caar binding))))))
        (error "Invalid let binding")))))

(defun validate-defclass-form (form)
  "Validate defclass form syntax"
  (when (< (length form) 3)
    (error "defclass requires at least name, superclasses, and slots")))

(defun check-types (text uri)
  "Check type consistency and return diagnostics"
  (let ((diagnostics '()))
    (handler-case
        (with-input-from-string (stream text)
          (loop for form = (read stream nil :eof)
                until (eq form :eof)
                do (check-form-types form uri diagnostics)))
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

(defun valid-type-p (type-spec)
  "Check if a type specification is valid"
  (cond
    ((keywordp type-spec)
     (member type-spec tycl::*valid-types*))
    ((consp type-spec)
     (if (keywordp (car type-spec))
         ;; Generic type like (:list (:integer))
         (and (member (car type-spec) tycl::*valid-types*)
              (every #'valid-type-p (cdr type-spec)))
         ;; Union type like (:integer :string)
         (every #'valid-type-p type-spec)))
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
