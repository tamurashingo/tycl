;;;; TyCL Type Annotation Class
;;;; Represents type-annotated symbols during transpilation

(in-package #:tycl/annotation)

(defclass type-annotation ()
  ((symbol
    :initarg :symbol
    :accessor annotation-symbol
    :documentation "The actual symbol")
   (type
    :initarg :type
    :accessor annotation-type
    :documentation "The type information"))
  (:documentation "Represents [symbol type] parsed from TyCL source"))

(defun type-annotation-p (obj)
  "Check if OBJ is a type-annotation"
  (typep obj 'type-annotation))

(defun make-type-annotation (symbol type)
  "Create a new type-annotation instance"
  (make-instance 'type-annotation :symbol symbol :type type))
