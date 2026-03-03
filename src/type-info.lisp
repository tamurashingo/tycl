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

;;; Type Alias Info

(defclass type-alias-info (type-info)
  ((expanded-type :initarg :expanded-type
                  :accessor alias-expanded-type
                  :documentation "The type this alias expands to")
   (type-params :initarg :type-params
                :accessor alias-type-params
                :initform nil
                :documentation "List of type parameter names (strings), e.g. (\"T\") or (\"A\" \"B\")"))
  (:default-initargs :kind :type-alias)
  (:documentation "Type information for type aliases defined by deftype-tycl"))

;;; Type Database

(defclass type-database ()
  ((entries :initform (make-hash-table :test 'equal)
            :accessor db-entries
            :documentation "Hash table: (package . symbol) -> type-info")
   (package-index :initform (make-hash-table :test 'equal)
                  :accessor db-package-index
                  :documentation "Hash table: package -> list of symbols")
   (type-aliases :initform (make-hash-table :test 'equal)
                 :accessor db-type-aliases
                 :documentation "Hash table: (package . alias-name) -> expanded-type")
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

;;; Type Alias Operations

(defun make-type-alias-info (package symbol expanded-type &key source-location type-params)
  "Create and register a type alias"
  (let* ((key (make-entry-key package symbol))
         (db *type-database*))
    ;; Store alias mapping for fast lookup
    (setf (gethash key (db-type-aliases db)) expanded-type)
    ;; Also register as type-info entry for serialization and LSP
    (register-type-info
     (make-instance 'type-alias-info
                    :package package
                    :symbol symbol
                    :expanded-type expanded-type
                    :type-params type-params
                    :source-location source-location))))

(defun lookup-type-alias (package alias-name)
  "Look up a type alias. Returns the expanded type or NIL if not found."
  (let ((key (make-entry-key package alias-name)))
    (gethash key (db-type-aliases *type-database*))))

(defun substitute-type-params (template bindings)
  "Substitute type parameters in TEMPLATE with actual types from BINDINGS.
   TEMPLATE: type template (e.g. (:list (T)))
   BINDINGS: alist of (param-name-string . actual-type) (e.g. ((\"T\" . :string)))"
  (cond
    ((keywordp template) template)
    ((symbolp template)
     (let ((binding (assoc (string-upcase (symbol-name template)) bindings :test #'string=)))
       (if binding (cdr binding) template)))
    ((stringp template)
     (let ((binding (assoc (string-upcase template) bindings :test #'string=)))
       (if binding (cdr binding) template)))
    ((consp template)
     (mapcar (lambda (sub) (substitute-type-params sub bindings)) template))
    (t template)))

(defun resolve-type-alias (type-spec &optional (package *current-package*) (depth 0))
  "Resolve a type specification, expanding any type aliases recursively.
   Handles recursive aliases with depth limit to prevent infinite loops.
   Also handles parametric type application: (result :string) -> (:list (:string))."
  (when (> depth 50)
    (warn "Type alias resolution depth limit reached for ~S" type-spec)
    (return-from resolve-type-alias type-spec))
  (cond
    ;; Keywords are built-in types, never aliases
    ((keywordp type-spec) type-spec)
    ;; Non-keyword symbol: could be a type alias
    ((symbolp type-spec)
     (let ((expanded (lookup-type-alias package (string-upcase (symbol-name type-spec)))))
       (if expanded
           (resolve-type-alias expanded package (1+ depth))
           type-spec)))
    ;; String: could be a type alias name
    ((stringp type-spec)
     (let ((expanded (lookup-type-alias package (string-upcase type-spec))))
       (if expanded
           (resolve-type-alias expanded package (1+ depth))
           type-spec)))
    ;; Composite type: check for parametric type application first
    ((consp type-spec)
     (let* ((head (car type-spec))
            (head-name (cond ((symbolp head) (string-upcase (symbol-name head)))
                             ((stringp head) (string-upcase head))
                             (t nil)))
            (alias-info (when head-name
                          (let ((key (make-entry-key package head-name)))
                            (gethash key (db-entries *type-database*))))))
       (if (and alias-info
                (typep alias-info 'type-alias-info)
                (alias-type-params alias-info))
           ;; Parametric type application: bind params and expand
           (let* ((params (alias-type-params alias-info))
                  (args (cdr type-spec))
                  (bindings (mapcar #'cons params
                                    (mapcar (lambda (a) (resolve-type-alias a package depth))
                                            args))))
             (resolve-type-alias
              (substitute-type-params (alias-expanded-type alias-info) bindings)
              package (1+ depth)))
           ;; Normal composite type: resolve each element
           (cons (resolve-type-alias (car type-spec) package depth)
                 (mapcar (lambda (sub) (resolve-type-alias sub package depth))
                         (cdr type-spec))))))
    ;; Anything else: return as-is
    (t type-spec)))

(defun get-package-type-aliases (package)
  "Get all type aliases defined in a package. Returns alist of (name . expanded-type)."
  (let ((aliases nil)
        (prefix (string-upcase package)))
    (maphash (lambda (key expanded-type)
               (when (string= (car key) prefix)
                 (push (cons (cdr key) expanded-type) aliases)))
             (db-type-aliases *type-database*))
    (nreverse aliases)))

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
