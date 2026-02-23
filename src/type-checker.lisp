;;;; TyCL Type Checker
;;;; Optional type checking for TyCL source code

(in-package #:tycl/type-checker)

(defvar *type-check-errors* nil
  "List of type checking errors found")

(defvar *enable-type-checking* nil
  "If true, perform type checking during transpilation")

(defvar *type-environment* nil
  "Type environment: alist of symbol -> type for local bindings")

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

(defun check-form (form &optional env)
  "Check types in a single form.
   ENV is an optional type environment (alist of symbol -> type).
   Returns T if no errors, NIL if errors found."
  (declare (ignore env))
  ;; TODO: Implement actual type checking logic
  ;; For now, just verify that type annotations are valid
  (cond
    ((type-annotation-p form)
     (let ((type (annotation-type form)))
       ;; Check if type is valid
       (unless (valid-type-p type)
         (record-type-error form
                           (format nil "Invalid type: ~S" type)))
       t))
    
    ((consp form)
     (every #'check-form form))
    
    (t t)))

(defun valid-type-p (type)
  "Check if TYPE is a valid TyCL type.
   This is a basic check - can be extended later."
  (or
   ;; Basic type keywords
   (member type '(:integer :float :double-float :rational :number
                  :string :character :boolean :symbol :keyword
                  :list :vector :array :hash-table :cons
                  :stream :pathname :function :t :void :null :any))
   ;; User-defined type (non-keyword symbol)
   (and (symbolp type) (not (keywordp type)))
   ;; Generic/Union type: (:integer :string) or (:list (:integer))
   (and (consp type)
        (every #'valid-type-p type))))

(defun check-string (tycl-string)
  "Check types in TyCL source code string.
   Returns T if no errors, NIL if errors found.
   Errors are stored in *TYPE-CHECK-ERRORS*."
  (clear-type-errors)
  (let ((*readtable* *tycl-readtable*))
    (with-input-from-string (in tycl-string)
      (loop for form = (read in nil :eof)
            until (eq form :eof)
            do (check-form form))))
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

;;; Type Consistency Checking

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

(defun infer-type (expr &optional env)
  "Infer the type of an expression.
   This is a basic implementation - can be extended."
  (cond
    ;; Literal values
    ((integerp expr) :integer)
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
    
    ;; Function call
    ((and (consp expr) (symbolp (first expr)))
     (let ((func-info (tycl:get-type-info *current-package* (string-upcase (symbol-name (first expr))))))
       (if (and func-info (typep func-info 'tycl:function-type-info))
           (tycl:function-return-type func-info)
           :t)))
    
    ;; Default
    (t :t)))

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

(defvar *current-package* "COMMON-LISP-USER"
  "Current package for type checking")
