;;;; Type Information Data Structures
;;;; Defines classes for storing type information extracted during transpilation

(in-package #:tycl)

;;; Base Type Info Class

(defclass type-info ()
  ((package :initarg :package
            :accessor type-info-package
            :type string
            :documentation "Package name where the symbol is defined")
   (symbol :initarg :symbol
           :accessor type-info-symbol
           :type string
           :documentation "Symbol name")
   (kind :initarg :kind
         :accessor type-info-kind
         :type keyword
         :documentation "Kind of symbol: :value, :function, :method, :class")
   (source-location :initarg :source-location
                    :accessor type-info-source-location
                    :initform nil
                    :documentation "Source file and position (optional)"))
  (:documentation "Base class for all type information"))

;;; Value Type Info (variables, constants)

(defclass value-type-info (type-info)
  ((type-spec :initarg :type-spec
              :accessor value-type-spec
              :documentation "Type specification"))
  (:default-initargs :kind :value)
  (:documentation "Type information for variables and constants"))

;;; Function Type Info

(defclass function-type-info (type-info)
  ((params :initarg :params
           :accessor function-params
           :initform nil
           :type list
           :documentation "List of parameter info: ((:name NAME :type TYPE) ...)")
   (return-type :initarg :return-type
                :accessor function-return-type
                :initform :t
                :documentation "Return type specification"))
  (:default-initargs :kind :function)
  (:documentation "Type information for functions"))

;;; Method Type Info

(defclass method-type-info (function-type-info)
  ((specializers :initarg :specializers
                 :accessor method-specializers
                 :initform nil
                 :type list
                 :documentation "List of specializer types"))
  (:default-initargs :kind :method)
  (:documentation "Type information for methods"))

;;; Class Type Info

(defclass class-type-info (type-info)
  ((slots :initarg :slots
          :accessor class-slots
          :initform nil
          :type list
          :documentation "List of slot info: ((:name NAME :type TYPE) ...)")
   (superclasses :initarg :superclasses
                 :accessor class-superclasses
                 :initform nil
                 :type list
                 :documentation "List of superclass names"))
  (:default-initargs :kind :class)
  (:documentation "Type information for classes and structures"))

;;; Type Database

(defclass type-database ()
  ((entries :initform (make-hash-table :test 'equal)
            :accessor db-entries
            :documentation "Hash table: (package . symbol) -> type-info")
   (package-index :initform (make-hash-table :test 'equal)
                  :accessor db-package-index
                  :documentation "Hash table: package -> list of symbols")
   (version :initform 1
            :accessor db-version
            :type integer)
   (timestamp :initform (get-universal-time)
             :accessor db-timestamp))
  (:documentation "Database of type information"))

;;; Valid Types

(defvar *valid-types*
  '(:integer :float :double-float :rational :number
    :string :character :simple-string
    :boolean :symbol :keyword
    :list :vector :array :hash-table :cons
    :stream :pathname :function :t :void :null :any)
  "List of valid TyCL type keywords")

;;; Global Type Database Instance

(defvar *type-database* (make-instance 'type-database)
  "Global type information database")

;;; Type Database Operations

(defun make-entry-key (package symbol)
  "Create a key for the type database entry"
  (cons (string-upcase package) (string-upcase symbol)))

(defun register-type-info (type-info)
  "Register type information in the global database"
  (let* ((pkg (type-info-package type-info))
         (sym (type-info-symbol type-info))
         (key (make-entry-key pkg sym))
         (db *type-database*))
    ;; Add to entries
    (setf (gethash key (db-entries db)) type-info)
    ;; Update package index
    (pushnew sym (gethash pkg (db-package-index db) nil) :test #'string=)
    type-info))

(defun lookup-type-info (package symbol)
  "Look up type information for a symbol"
  (let ((key (make-entry-key package symbol)))
    (gethash key (db-entries *type-database*))))

(defun get-type-info (package symbol)
  "Alias for lookup-type-info"
  (lookup-type-info package symbol))

(defun get-package-symbols (package)
  "Get all symbols defined in a package"
  (gethash (string-upcase package) (db-package-index *type-database*)))

(defun clear-type-database ()
  "Clear all type information from the database"
  (setf *type-database* (make-instance 'type-database)))

;;; Type Info Constructors

(defun make-value-type-info (package symbol type-spec &key source-location)
  "Create and register a value type info"
  (register-type-info
   (make-instance 'value-type-info
                  :package package
                  :symbol symbol
                  :type-spec type-spec
                  :source-location source-location)))

(defun make-function-type-info (package symbol params return-type &key source-location)
  "Create and register a function type info"
  (register-type-info
   (make-instance 'function-type-info
                  :package package
                  :symbol symbol
                  :params params
                  :return-type return-type
                  :source-location source-location)))

(defun make-method-type-info (package symbol params return-type specializers &key source-location)
  "Create and register a method type info"
  (register-type-info
   (make-instance 'method-type-info
                  :package package
                  :symbol symbol
                  :params params
                  :return-type return-type
                  :specializers specializers
                  :source-location source-location)))

(defun make-class-type-info (package symbol slots superclasses &key source-location)
  "Create and register a class type info"
  (register-type-info
   (make-instance 'class-type-info
                  :package package
                  :symbol symbol
                  :slots slots
                  :superclasses superclasses
                  :source-location source-location)))

;;; Type Specification Utilities

(defun normalize-type-spec (type-spec)
  "Normalize a type specification to canonical form"
  (cond
    ;; Simple type: :integer -> :integer
    ((keywordp type-spec) type-spec)
    ;; Symbol type: user -> USER
    ((symbolp type-spec) (string-upcase (symbol-name type-spec)))
    ;; Union type: (:integer :string) -> (:union :integer :string)
    ((and (listp type-spec)
          (not (keywordp (first type-spec))))
     (cons :union type-spec))
    ;; Generic type: (:list (:integer)) -> normalize recursively
    ((and (listp type-spec)
          (keywordp (first type-spec)))
     (cons (first type-spec)
           (mapcar #'normalize-type-spec (rest type-spec))))
    ;; Default
    (t type-spec)))

(defun type-spec-equal (spec1 spec2)
  "Compare two type specifications for equality"
  (equal (normalize-type-spec spec1)
         (normalize-type-spec spec2)))
