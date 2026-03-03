;;;; Type Extractor
;;;; Extracts type information from TyCL forms during transpilation

(in-package #:tycl)

;;; Current Context

(defvar *current-package* "COMMON-LISP-USER"
  "Current package being processed")

(defvar *current-file* nil
  "Current file being processed")

;;; Type Extraction from Forms

(defun extract-type-from-form (form &optional env)
  "Extract type information from a form and register it.
   ENV is an optional type environment for local scopes (not persisted)."
  (when (and (listp form) (symbolp (first form)))
    (let ((operator (first form)))
      (cond
        ((eq operator 'defun) (extract-defun-type form))
        ((eq operator 'defvar) (extract-defvar-type form))
        ((eq operator 'defparameter) (extract-defparameter-type form))
        ((eq operator 'defconstant) (extract-defconstant-type form))
        ((eq operator 'defclass) (extract-defclass-type form))
        ((eq operator 'defmethod) (extract-defmethod-type form))
        ((eq operator 'in-package) (update-current-package form))
        ;; Local bindings (not persisted, used for type checking)
        ((member operator '(let let*)) (extract-let-bindings form env))
        ((member operator '(flet labels)) (extract-local-functions form env))
        ;; Check for custom hooks
        ((find-type-extractor operator)
         (extract-with-hook form operator))))))

;;; defun Type Extraction

(defun extract-defun-type (form)
  "Extract type information from defun form
   (defun [name return-type] (params...) body...)"
  (when (< (length form) 3)
    (return-from extract-defun-type nil))
  (let* ((name-spec (second form))
         (params-spec (third form))
         (name (if (tycl/annotation:type-annotation-p name-spec)
                   (tycl/annotation:annotation-symbol name-spec)
                   name-spec))
         (return-type (if (tycl/annotation:type-annotation-p name-spec)
                          (tycl/annotation:annotation-type name-spec)
                          :t))
         (params (extract-params-types params-spec)))
    (when (and name (symbolp name))
      (make-function-type-info
       *current-package*
       (string-upcase (symbol-name name))
       params
       return-type
       :source-location *current-file*))))

(defun extract-params-types (params-spec)
  "Extract parameter types from parameter list
   (([x :integer] [y :string] z) -> ((:name X :type :integer) (:name Y :type :string) (:name Z :type :t))"
  (loop for param in params-spec
        collect (cond
                  ;; Type annotation: [x :integer]
                  ((tycl/annotation:type-annotation-p param)
                   (list :name (string-upcase (symbol-name (tycl/annotation:annotation-symbol param)))
                         :type (tycl/annotation:annotation-type param)))
                  ;; Regular symbol: x
                  ((symbolp param)
                   (list :name (string-upcase (symbol-name param))
                         :type :t))
                  ;; Unknown
                  (t
                   (warn "Unknown parameter spec: ~S" param)
                   (list :name "UNKNOWN" :type :t)))))

;;; defvar/defparameter/defconstant Type Extraction

(defun extract-defvar-type (form)
  "Extract type information from defvar form
   (defvar [*name* type] value)"
  (when (< (length form) 2)
    (return-from extract-defvar-type nil))
  (let* ((name-spec (second form))
         (name (if (tycl/annotation:type-annotation-p name-spec)
                   (tycl/annotation:annotation-symbol name-spec)
                   name-spec))
         (type (if (tycl/annotation:type-annotation-p name-spec)
                   (tycl/annotation:annotation-type name-spec)
                   :t)))
    (when (and name (symbolp name))
      (make-value-type-info
       *current-package*
       (string-upcase (symbol-name name))
       type
       :source-location *current-file*))))

(defun extract-defparameter-type (form)
  "Extract type information from defparameter form"
  (extract-defvar-type form))

(defun extract-defconstant-type (form)
  "Extract type information from defconstant form"
  (extract-defvar-type form))

;;; defclass Type Extraction

(defun extract-defclass-type (form)
  "Extract type information from defclass form
   (defclass name (supers...) (slots...))"
  (when (< (length form) 4)
    (return-from extract-defclass-type nil))
  (let* ((name (second form))
         (supers (third form))
         (slots-spec (fourth form))
         (slots (extract-slots-types slots-spec)))
    (when (and name (symbolp name))
      (make-class-type-info
       *current-package*
       (string-upcase (symbol-name name))
       slots
       (mapcar (lambda (s) (string-upcase (symbol-name s))) supers)
       :source-location *current-file*))))

(defun extract-slots-types (slots-spec)
  "Extract slot types from defclass slots
   ((([name :string] :initarg :name) (age)) -> ((:name NAME :type :string) (:name AGE :type :t))"
  (loop for slot in slots-spec
        for slot-name-spec = (if (listp slot) (first slot) slot)
        for slot-name = (if (tycl/annotation:type-annotation-p slot-name-spec)
                            (tycl/annotation:annotation-symbol slot-name-spec)
                            slot-name-spec)
        for slot-type = (if (tycl/annotation:type-annotation-p slot-name-spec)
                            (tycl/annotation:annotation-type slot-name-spec)
                            :t)
        collect (list :name (string-upcase (symbol-name slot-name))
                      :type slot-type)))

;;; defmethod Type Extraction

(defun extract-defmethod-type (form)
  "Extract type information from defmethod form
   (defmethod [name return-type] (params...) body...)"
  (when (< (length form) 3)
    (return-from extract-defmethod-type nil))
  (let* ((name-spec (second form))
         (params-spec (third form))
         (name (if (tycl/annotation:type-annotation-p name-spec)
                   (tycl/annotation:annotation-symbol name-spec)
                   name-spec))
         (return-type (if (tycl/annotation:type-annotation-p name-spec)
                          (tycl/annotation:annotation-type name-spec)
                          :t))
         (params (extract-params-types params-spec))
         (specializers (extract-method-specializers params-spec)))
    (when (and name (symbolp name))
      (make-method-type-info
       *current-package*
       (string-upcase (symbol-name name))
       params
       return-type
       specializers
       :source-location *current-file*))))

(defun extract-method-specializers (params-spec)
  "Extract method specializers from parameter list"
  (loop for param in params-spec
        collect (if (tycl/annotation:type-annotation-p param)
                    (let ((type (tycl/annotation:annotation-type param)))
                      (if (keywordp type) 
                          type 
                          (string-upcase (symbol-name type))))
                    :t)))

;;; Package Management

(defun update-current-package (form)
  "Update *current-package* from (in-package ...) form"
  (let ((package-designator (second form)))
    (setf *current-package*
          (string-upcase
           (etypecase package-designator
             (string package-designator)
             (symbol (symbol-name package-designator))
             (keyword (symbol-name package-designator)))))
    nil))

;;; Local Scope Management (for type checking, not persisted)

(defun extract-let-bindings (form env)
  "Extract type information from let/let* bindings.
   Returns an extended environment with local variable types.
   These are NOT persisted to the type database."
  (let* ((bindings (second form))
         (body (cddr form))
         (new-env env))
    ;; Extract types from bindings
    (dolist (binding bindings)
      (when (listp binding)
        (let* ((var-spec (first binding))
               (var-name (if (tycl/annotation:type-annotation-p var-spec)
                             (tycl/annotation:annotation-symbol var-spec)
                             var-spec))
               (var-type (if (tycl/annotation:type-annotation-p var-spec)
                             (tycl/annotation:annotation-type var-spec)
                             :t)))
          (push (cons var-name var-type) new-env))))
    ;; Process body with extended environment (for type checking)
    (dolist (expr body)
      (when (listp expr)
        (extract-type-from-form expr new-env)))
    ;; Return environment for nested scopes
    new-env))

(defun extract-local-functions (form env)
  "Extract type information from flet/labels local functions.
   Returns an extended environment with local function types.
   These are NOT persisted to the type database."
  (let* ((bindings (second form))
         (body (cddr form))
         (new-env env))
    ;; Extract types from local function definitions
    (dolist (binding bindings)
      (when (listp binding)
        (let* ((name-spec (first binding))
               (params-spec (second binding))
               (func-name (if (tycl/annotation:type-annotation-p name-spec)
                              (tycl/annotation:annotation-symbol name-spec)
                              name-spec))
               (return-type (if (tycl/annotation:type-annotation-p name-spec)
                                (tycl/annotation:annotation-type name-spec)
                                :t)))
          ;; Store function type in environment
          (push (cons func-name `(:function ,return-type)) new-env))))
    ;; Process body with extended environment
    (dolist (expr body)
      (when (listp expr)
        (extract-type-from-form expr new-env)))
    ;; Return environment for nested scopes
    new-env))

;;; Type Extractor Hooks

(defstruct type-extractor-hook
  "Type extraction hook for custom macros.
   The type-extractor function should return a list of type info plists:
   ((:value :symbol \"NAME\" :type :integer)
    (:function :symbol \"GET-NAME\" :params (...) :return :integer))"
  (macro-name nil :type symbol)
  (type-extractor nil :type function)
  (enabled t :type boolean))

(defvar *type-extractor-hooks* (make-hash-table :test 'eq)
  "Registry of type extractor hooks: macro-name -> hook")

(defun register-type-extractor (macro-name &key type-extractor)
  "Register a type extractor hook for a custom macro.
   type-extractor: function that takes a form and returns a list of type info plists.
   Each plist should have :kind (one of :value :function :class :method), :symbol, and type fields."
  (setf (gethash macro-name *type-extractor-hooks*)
        (make-type-extractor-hook
         :macro-name macro-name
         :type-extractor type-extractor))
  macro-name)

(defun unregister-type-extractor (macro-name)
  "Unregister a type extractor hook"
  (remhash macro-name *type-extractor-hooks*))

(defun find-type-extractor (macro-name)
  "Find a registered type extractor hook"
  (gethash macro-name *type-extractor-hooks*))

(defun extract-with-hook (form macro-name)
  "Extract type information using a registered hook.
   The hook's type-extractor function should return a list of type info plists."
  (let ((hook (find-type-extractor macro-name)))
    (when (and hook (type-extractor-hook-enabled hook))
      (let ((type-infos (funcall (type-extractor-hook-type-extractor hook) form)))
        ;; type-infos is a list of plists, each describing one type definition
        (dolist (type-info type-infos)
          (when type-info
            (let ((kind (getf type-info :kind))
                  (symbol-name (getf type-info :symbol)))
              (case kind
                (:function
                 (register-type-info
                  (make-function-type-info
                   *current-package*
                   (string-upcase (if (symbolp symbol-name)
                                      (symbol-name symbol-name)
                                      symbol-name))
                   (getf type-info :params)
                   (getf type-info :return)
                   :source-location *current-file*)))
                (:value
                 (register-type-info
                  (make-value-type-info
                   *current-package*
                   (string-upcase (if (symbolp symbol-name)
                                      (symbol-name symbol-name)
                                      symbol-name))
                   (getf type-info :type)
                   :source-location *current-file*)))
                (:class
                 (register-type-info
                  (make-class-type-info
                   *current-package*
                   (string-upcase (if (symbolp symbol-name)
                                      (symbol-name symbol-name)
                                      symbol-name))
                   (getf type-info :slots)
                   (getf type-info :superclasses '())
                   :source-location *current-file*)))
                (:method
                 (register-type-info
                  (make-method-type-info
                   *current-package*
                   (string-upcase (if (symbolp symbol-name)
                                      (symbol-name symbol-name)
                                      symbol-name))
                   (getf type-info :params)
                   (getf type-info :return)
                   (getf type-info :specializers)
                   :source-location *current-file*)))))))
        ;; Return the first type info for backwards compatibility
        (first type-infos)))))

;;; Hook Configuration Loading

(defvar *loaded-hook-files* nil
  "List of hook files that have been loaded (to avoid duplicate loading)")

(defun load-hook-configuration (file)
  "Load type extractor hooks from a configuration file.
   Avoids loading the same file multiple times.
   Returns T if loaded successfully or already loaded."
  (let ((canonical-path (truename file)))
    (cond
      ((not (probe-file canonical-path))
       (warn "Hook configuration file not found: ~A" canonical-path)
       nil)
      ((member canonical-path *loaded-hook-files* :test #'equal)
       ;; Already loaded - return success
       t)
      (t
       ;; Load the file
       (handler-case
           (progn
             (format *error-output* "~&; Loading TyCL hooks from ~A~%" canonical-path)
             (load canonical-path)
             (push canonical-path *loaded-hook-files*)
             t)
         (error (e)
           (warn "Failed to load hook configuration from ~A: ~A" canonical-path e)
           nil))))))

(defun find-and-load-hooks (directory)
  "Find and load tycl-hooks.lisp in directory and its parent directories.
   Searches up to the root directory or until finding a hooks file."
  (let ((dir (uiop:ensure-directory-pathname directory))
        (max-depth 50))  ; Safety limit to prevent infinite loops
    (loop
      for current-dir = dir then parent-dir
      for hooks-file = (merge-pathnames "tycl-hooks.lisp" current-dir)
      for parent-dir = (uiop:pathname-parent-directory-pathname current-dir)
      for depth from 0
      
      when (>= depth max-depth)
        do (warn "Maximum directory depth reached while searching for hooks")
           (return nil)
      
      when (and hooks-file (probe-file hooks-file))
        do (load-hook-configuration hooks-file)
           (return t)
      
      ;; Stop at root or when parent is the same as current
      until (or (null parent-dir)
                (equal current-dir parent-dir)))))

(defun clear-hook-configuration ()
  "Clear all loaded hook configurations and reset the loaded files list.
   Useful for testing or reloading hooks."
  (setf *loaded-hook-files* nil)
  (clrhash *type-extractor-hooks*))
