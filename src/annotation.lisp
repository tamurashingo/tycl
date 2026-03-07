;;;; TyCL Type Annotation Class
;;;; Represents type-annotated symbols during transpilation

(in-package #:tycl/annotation)

;;; Type Parameters class (from <T>, <A B>)

(defclass type-params ()
  ((entries
    :initarg :entries
    :accessor type-params-entries
    :initform nil
    :type list
    :documentation "List of type variable symbols, e.g. (T) or (A B)"))
  (:documentation "Represents type parameters from <T>, <A B>"))

(defun type-params-p (obj)
  "Check if OBJ is a type-params"
  (typep obj 'type-params))

(defun make-type-params (&key entries)
  "Create a new type-params instance"
  (make-instance 'type-params :entries entries))

;;; Type Annotation class

(defclass type-annotation ()
  ((symbol
    :initarg :symbol
    :accessor annotation-symbol
    :documentation "The actual symbol")
   (type
    :initarg :type
    :accessor annotation-type
    :documentation "The type information")
   (type-params
    :initarg :type-params
    :accessor annotation-type-params
    :initform nil
    :documentation "Type parameters from <T>, <A B> notation"))
  (:documentation "Represents [symbol type] or [symbol <type-params> type] parsed from TyCL source"))

(defun type-annotation-p (obj)
  "Check if OBJ is a type-annotation"
  (typep obj 'type-annotation))

(defun make-type-annotation (symbol type &key type-params)
  "Create a new type-annotation instance"
  (make-instance 'type-annotation :symbol symbol :type type :type-params type-params))
