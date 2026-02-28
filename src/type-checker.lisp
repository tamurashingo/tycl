;;;; TyCL Type Checker
;;;; Optional type checking for TyCL source code

(in-package #:tycl/type-checker)

(defvar *type-check-errors* nil
  "List of type checking errors found")

(defvar *enable-type-checking* nil
  "Controls type checking behavior:
   NIL     - no checking (default, backward compatible)
   T/:WARN - check and warn, but transpilation continues
   :ERROR  - check and signal error if type errors found")

(defvar *type-environment* nil
  "Type environment: alist of symbol -> type for local bindings")

(defvar *current-package* "COMMON-LISP-USER"
  "Current package for type checking")

(defclass type-error-info ()
  ((form
    :initarg :form
    :accessor error-form
    :documentation "The form that caused the error")
   (message
    :initarg :message
    :accessor error-message
    :documentation "Error message")
   (location
    :initarg :location
    :initform nil
    :accessor error-location
    :documentation "Source location (file, line, column)"))
  (:documentation "Information about a type checking error"))

(defun make-type-error (form message &optional location)
  "Create a new type-error-info instance"
  (make-instance 'type-error-info
                 :form form
                 :message message
                 :location location))

(defun record-type-error (form message &optional location)
  "Record a type checking error"
  (push (make-type-error form message location) *type-check-errors*))

(defun clear-type-errors ()
  "Clear all recorded type errors"
  (setf *type-check-errors* nil))

;;; Type Validation

(defun valid-type-p (type)
  "Check if TYPE is a valid TyCL type.
   This is a basic check - can be extended later."
  (or
   ;; Basic type keywords
   (member type tycl::*valid-types*)
   ;; User-defined type (non-keyword symbol)
   (and (symbolp type) (not (keywordp type)))
   ;; Generic/Union type: (:integer :string) or (:list (:integer))
   (and (consp type)
        (every #'valid-type-p type))))

;;; Type Compatibility

(defun type-compatible-p (actual expected)
  "Check if ACTUAL type is compatible with EXPECTED type.
   Handles union types and :t (any type)."
  (cond
    ;; Any type accepts everything
    ((or (eq expected :t) (eq expected :any)) t)
    ((or (eq actual :t) (eq actual :any)) t)

    ;; Exact match
    ((equal actual expected) t)

    ;; Union type: actual must be one of the union members
    ((and (consp expected) (not (consp actual)))
     (member actual expected :test #'equal))

    ;; Generic types: check base and parameters
    ((and (consp actual) (consp expected))
     (and (equal (first actual) (first expected))
          (= (length actual) (length expected))
          (every #'type-compatible-p (rest actual) (rest expected))))

    ;; Numeric compatibility
    ((and (member actual '(:integer :float :double-float :rational))
          (member expected '(:number)))
     t)

    ;; Default: incompatible
    (t nil)))

;;; Type Inference

(defun infer-type (expr &optional env)
  "Infer the type of an expression.
   ENV is a type environment (alist of symbol -> type)."
  (cond
    ;; Literal values
    ((integerp expr) :integer)
    ((typep expr 'double-float) :double-float)
    ((floatp expr) :float)
    ((stringp expr) :string)
    ((null expr) :null)
    ((eq expr t) :boolean)
    ((keywordp expr) :keyword)

    ;; Variables: lookup in environment
    ((symbolp expr)
     (or (cdr (assoc expr env))
         (let ((var-info (tycl:get-type-info *current-package* (string-upcase (symbol-name expr)))))
           (if (and var-info (typep var-info 'tycl:value-type-info))
               (tycl:value-type-spec var-info)
               :t))))

    ;; Type annotation: [expr type]
    ((tycl/annotation:type-annotation-p expr)
     (tycl/annotation:annotation-type expr))

    ;; Compound forms
    ((consp expr)
     (let ((op (first expr)))
       (cond
         ;; let/let* form: type is the type of the last body expression
         ((member op '(let let*))
          (let ((body (cddr expr)))
            (if body
                (infer-type (car (last body)) env)
                :null)))

         ;; if form: unify then/else types
         ((eq op 'if)
          (let ((then-type (infer-type (third expr) env))
                (else-type (if (fourth expr)
                               (infer-type (fourth expr) env)
                               :null)))
            (if (type-compatible-p then-type else-type)
                then-type
                :t)))

         ;; lambda: return :function
         ((eq op 'lambda) :function)

         ;; Function call: check local env first, then DB
         ((symbolp op)
          (let ((local-info (cdr (assoc op env))))
            (cond
              ;; Local function from env (stored as (:function return-type))
              ((and (consp local-info) (eq (first local-info) :function))
               (second local-info))
              ;; DB registered function
              (t
               (let ((func-info (tycl:get-type-info *current-package*
                                                     (string-upcase (symbol-name op)))))
                 (if (and func-info (typep func-info 'tycl:function-type-info))
                     (tycl:function-return-type func-info)
                     :t))))))

         ;; Default
         (t :t))))

    ;; Default
    (t :t)))

;;; Environment Building

(defun build-param-env (params-spec env)
  "Build a type environment from a parameter list specification.
   Returns a new env extended with parameter type bindings."
  (let ((new-env env))
    (dolist (param params-spec)
      (cond
        ;; Type annotation: [x :integer]
        ((tycl/annotation:type-annotation-p param)
         (let ((name (tycl/annotation:annotation-symbol param))
               (type (tycl/annotation:annotation-type param)))
           (unless (valid-type-p type)
             (record-type-error param
                                (format nil "Invalid parameter type: ~S" type)))
           (push (cons name type) new-env)))
        ;; Regular symbol: x (untyped, treated as :t)
        ((symbolp param)
         (push (cons param :t) new-env))))
    new-env))

;;; Form Checking Functions

(defun check-defun (form env)
  "Check types in a defun/defmethod form.
   (defun [name return-type] ([params...]) body...)
   Returns the updated env with the function registered."
  (let* ((name-spec (second form))
         (params-spec (third form))
         (body (cdddr form))
         (func-name (if (tycl/annotation:type-annotation-p name-spec)
                        (tycl/annotation:annotation-symbol name-spec)
                        name-spec))
         (return-type (if (tycl/annotation:type-annotation-p name-spec)
                          (tycl/annotation:annotation-type name-spec)
                          :t)))
    ;; Validate return type
    (when (and (tycl/annotation:type-annotation-p name-spec)
               (not (valid-type-p return-type)))
      (record-type-error name-spec
                          (format nil "Invalid return type: ~S" return-type)))
    ;; Build parameter environment
    (let ((body-env (build-param-env params-spec env)))
      ;; Check body forms
      (dolist (expr body)
        (setf body-env (check-form expr body-env)))
      ;; Check return type consistency: infer from last body expression
      (when (and body (not (eq return-type :t)))
        (let ((last-expr (car (last body)))
              (inferred (infer-type (car (last body)) body-env)))
          (unless (type-compatible-p inferred return-type)
            (record-type-error last-expr
                                (format nil "Return type mismatch: declared ~S but body returns ~S"
                                        return-type inferred))))))
    ;; Register function in env for forward references within local scope
    (push (cons func-name `(:function ,return-type)) env)
    env))

(defun check-let (form env)
  "Check types in a let/let* form.
   (let (([x :integer] value) ...) body...)
   Returns env (outer env unchanged)."
  (let* ((operator (first form))
         (bindings (second form))
         (body (cddr form))
         (body-env env))
    ;; Process bindings
    (dolist (binding bindings)
      (cond
        ;; (var-spec value)
        ((and (listp binding) (>= (length binding) 2))
         (let* ((var-spec (first binding))
                (init-expr (second binding))
                (var-name (if (tycl/annotation:type-annotation-p var-spec)
                              (tycl/annotation:annotation-symbol var-spec)
                              var-spec))
                (declared-type (if (tycl/annotation:type-annotation-p var-spec)
                                   (tycl/annotation:annotation-type var-spec)
                                   :t))
                ;; For let*, use body-env (accumulated); for let, use original env
                (infer-env (if (eq operator 'let*) body-env env))
                (init-type (infer-type init-expr infer-env)))
           ;; Validate declared type
           (when (and (tycl/annotation:type-annotation-p var-spec)
                      (not (valid-type-p declared-type)))
             (record-type-error var-spec
                                 (format nil "Invalid type: ~S" declared-type)))
           ;; Check type consistency
           (when (and (not (eq declared-type :t))
                      (not (eq init-type :t))
                      (not (type-compatible-p init-type declared-type)))
             (record-type-error binding
                                 (format nil "Type mismatch in binding: ~S declared as ~S but initialized with ~S"
                                         var-name declared-type init-type)))
           ;; Recursively check init-expr
           (check-form init-expr infer-env)
           ;; Add to body env
           (push (cons var-name declared-type) body-env)))
        ;; (var) or just a symbol binding - just add with :t
        ((listp binding)
         (let ((var-spec (first binding)))
           (when (symbolp var-spec)
             (push (cons var-spec :t) body-env))))
        ((symbolp binding)
         (push (cons binding :t) body-env))))
    ;; Check body with extended environment
    (dolist (expr body)
      (setf body-env (check-form expr body-env)))
    ;; Return original env (let doesn't leak bindings)
    env))

(defun check-flet (form env)
  "Check types in a flet/labels form.
   (flet (([name return-type] (params) body) ...) body...)
   Returns env (outer env unchanged)."
  (let* ((operator (first form))
         (bindings (second form))
         (body (cddr form))
         (body-env env))
    ;; For labels, we need to add all function names to env first
    (when (eq operator 'labels)
      (dolist (binding bindings)
        (when (listp binding)
          (let* ((name-spec (first binding))
                 (func-name (if (tycl/annotation:type-annotation-p name-spec)
                                (tycl/annotation:annotation-symbol name-spec)
                                name-spec))
                 (return-type (if (tycl/annotation:type-annotation-p name-spec)
                                  (tycl/annotation:annotation-type name-spec)
                                  :t)))
            (push (cons func-name `(:function ,return-type)) body-env)))))
    ;; Process each local function definition
    (dolist (binding bindings)
      (when (and (listp binding) (>= (length binding) 2))
        (let* ((name-spec (first binding))
               (params-spec (second binding))
               (func-body (cddr binding))
               (func-name (if (tycl/annotation:type-annotation-p name-spec)
                              (tycl/annotation:annotation-symbol name-spec)
                              name-spec))
               (return-type (if (tycl/annotation:type-annotation-p name-spec)
                                (tycl/annotation:annotation-type name-spec)
                                :t)))
          ;; Validate return type
          (when (and (tycl/annotation:type-annotation-p name-spec)
                     (not (valid-type-p return-type)))
            (record-type-error name-spec
                                (format nil "Invalid return type for local function: ~S" return-type)))
          ;; Build param env for the local function
          (let ((func-env (build-param-env params-spec
                                            (if (eq operator 'labels) body-env env))))
            ;; Check the local function's body
            (dolist (expr func-body)
              (setf func-env (check-form expr func-env)))
            ;; Check return type consistency
            (when (and func-body (not (eq return-type :t)))
              (let ((inferred (infer-type (car (last func-body)) func-env)))
                (unless (type-compatible-p inferred return-type)
                  (record-type-error (first binding)
                                      (format nil "Return type mismatch in local function ~S: declared ~S but returns ~S"
                                              func-name return-type inferred))))))
          ;; For flet, add function to body-env after checking
          (when (eq operator 'flet)
            (push (cons func-name `(:function ,return-type)) body-env)))))
    ;; Check outer body with extended environment
    (dolist (expr body)
      (setf body-env (check-form expr body-env)))
    ;; Return original env
    env))

(defun check-lambda (form env)
  "Check types in a lambda form.
   (lambda ([params...]) body...)
   Returns env unchanged."
  (let* ((params-spec (second form))
         (body (cddr form))
         (body-env (build-param-env params-spec env)))
    ;; Check body
    (dolist (expr body)
      (setf body-env (check-form expr body-env)))
    env))

(defun check-function-call-form (form env)
  "Check a function call form.
   Recursively checks arguments and validates against DB if available."
  (let* ((func-name (first form))
         (args (rest form)))
    ;; Recursively check each argument
    (dolist (arg args)
      (check-form arg env))
    ;; Check against type database
    (let ((func-info (tycl:get-type-info *current-package*
                                          (string-upcase (symbol-name func-name)))))
      (when (and func-info (typep func-info 'tycl:function-type-info))
        (let ((params (tycl:function-params func-info)))
          ;; Check argument count
          (unless (= (length args) (length params))
            (record-type-error
             form
             (format nil "Function ~S: expected ~D arguments, got ~D"
                     func-name (length params) (length args)))
            (return-from check-function-call-form env))
          ;; Check argument types
          (loop for arg in args
                for param in params
                for expected-type = (getf param :type)
                for actual-type = (infer-type arg env)
                unless (type-compatible-p actual-type expected-type)
                do (record-type-error
                    arg
                    (format nil "Function ~S: argument type mismatch, expected ~S but got ~S"
                            func-name expected-type actual-type))))))
    ;; Also check against local env
    (let ((local-info (cdr (assoc func-name env))))
      (when (and (consp local-info) (eq (first local-info) :function))
        ;; Local function found, but we don't have param info for it
        ;; (only return type is stored in env)
        nil))
    env))

;;; Main Dispatcher

(defun check-form (form &optional env)
  "Check types in a single form.
   ENV is a type environment (alist of symbol -> type).
   Returns the (possibly extended) env."
  (cond
    ;; Type annotation
    ((type-annotation-p form)
     (let ((type (annotation-type form)))
       (unless (valid-type-p type)
         (record-type-error form
                             (format nil "Invalid type: ~S" type))))
     env)

    ;; Compound forms
    ((consp form)
     (let ((op (first form)))
       (cond
         ;; defun / defmethod
         ((member op '(defun defmethod))
          (check-defun form env))
         ;; let / let*
         ((member op '(let let*))
          (check-let form env))
         ;; flet / labels
         ((member op '(flet labels))
          (check-flet form env))
         ;; lambda
         ((eq op 'lambda)
          (check-lambda form env))
         ;; in-package
         ((eq op 'in-package)
          (let ((pkg (second form)))
            (setf *current-package*
                  (string-upcase
                   (etypecase pkg
                     (string pkg)
                     (symbol (symbol-name pkg))
                     (keyword (symbol-name pkg))))))
          env)
         ;; Other function calls (only if op is a symbol)
         ((symbolp op)
          (check-function-call-form form env))
         ;; Unknown compound form: recurse into elements
         (t env))))

    ;; Atoms: no checking needed
    (t env)))

;;; High-level API

(defun run-type-checks (forms)
  "Run type checks on a list of forms.
   Returns T if no errors, NIL if errors found.
   Errors are accumulated in *type-check-errors*."
  (let ((env nil))
    (dolist (form forms)
      (setf env (check-form form env))))
  (null *type-check-errors*))

(defun check-string (tycl-string)
  "Check types in TyCL source code string.
   Uses 2-pass approach: read all forms, extract types, then check.
   Returns T if no errors, NIL if errors found.
   Errors are stored in *TYPE-CHECK-ERRORS*."
  (clear-type-errors)
  (let ((*readtable* *tycl-readtable*)
        (forms nil))
    ;; Pass 1: Read all forms
    (with-input-from-string (in tycl-string)
      (loop for form = (read in nil :eof)
            until (eq form :eof)
            do (push form forms)))
    (setf forms (nreverse forms))
    ;; Pass 1.5: Extract type information (so forward references work)
    (let ((tycl:*current-package* *current-package*))
      (dolist (form forms)
        (tycl:extract-type-from-form form)))
    ;; Pass 2: Type check
    (run-type-checks forms))
  (null *type-check-errors*))

(defun check-file (input-file)
  "Check types in a .tycl file.
   Returns T if no errors, NIL if errors found.
   Prints errors to *standard-output*."
  (let ((tycl-source (uiop:read-file-string input-file))
        (result nil))
    (setf result (check-string tycl-source))
    (if result
        (format t "~&Type check passed: ~A~%" input-file)
        (progn
          (format t "~&Type check failed: ~A~%" input-file)
          (dolist (err (reverse *type-check-errors*))
            (format t "  Error: ~A~%    in: ~S~%"
                    (error-message err)
                    (error-form err)))))
    result))

;;; Legacy compatibility

(defun check-function-call (function-name args &optional env)
  "Check if a function call has correct argument types.
   ENV is a type environment for local variables."
  (let ((func-info (tycl:get-type-info *current-package* (string (string-upcase (symbol-name function-name))))))
    (when (and func-info (typep func-info 'tycl:function-type-info))
      (let ((params (tycl:function-params func-info)))
        ;; Check argument count
        (unless (= (length args) (length params))
          (record-type-error
           `(,function-name ,@args)
           (format nil "Expected ~D arguments, got ~D"
                   (length params) (length args)))
          (return-from check-function-call nil))

        ;; Check argument types
        (loop for arg in args
              for param in params
              for expected-type = (getf param :type)
              for actual-type = (infer-type arg env)
              unless (type-compatible-p actual-type expected-type)
              do (record-type-error
                  arg
                  (format nil "Type mismatch: expected ~S, got ~S"
                          expected-type actual-type))
                 (return-from check-function-call nil))))
    t))
