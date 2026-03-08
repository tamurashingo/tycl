;;;; Sample Project - Custom Macros
;;;; Demonstrates TyCL's register-type-extractor support

(in-package #:cl-user)
(defpackage #:sample-project/macros
  (:use #:cl)
  (:export #:defmodel #:define-api))
(in-package #:sample-project/macros)

(defmacro defmodel (name slots)
  "Define a simple model class with accessors.
   Each slot is (slot-name type-keyword), e.g. (name :string).
   Type keyword is used by tycl-hooks.lisp for type extraction, not by the macro itself."
  (let ((slot-defs
          (mapcar (lambda (spec)
                    (let* ((slot-name (first spec))
                           (initarg (intern (symbol-name slot-name) :keyword))
                           (accessor (intern (format nil "~A-~A" name slot-name))))
                      `(,slot-name :accessor ,accessor
                                   :initarg ,initarg
                                   :initform nil)))
                  slots)))
    `(defclass ,name ()
       ,slot-defs)))

(defmacro define-api (name params &body body)
  "Define an API function. Thin wrapper around defun."
  `(defun ,name ,params ,@body))
