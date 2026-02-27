;;;; TyCL ASDF Extension
;;;; Allows .tycl files to be used as components in ASDF systems

(in-package #:cl-user)

(defpackage #:tycl/asdf
  (:use #:cl #:asdf)
  (:export #:tycl-system
           #:tycl-file
           #:transpile-tycl-op
           #:copy-source-op))

(in-package #:tycl/asdf)

;;; ============================================================
;;; System class
;;; ============================================================

(defclass tycl-system (asdf:system)
  ((tycl-output-dir
    :initarg :tycl-output-dir
    :initform nil
    :accessor tycl-output-dir
    :documentation "Output directory for transpiled/copied files")
   (tycl-extract-types
    :initarg :tycl-extract-types
    :initform t
    :accessor tycl-extract-types-p
    :documentation "Whether to extract type information")
   (tycl-save-types
    :initarg :tycl-save-types
    :initform t
    :accessor tycl-save-types-p
    :documentation "Whether to generate .tycl-types files")
   (tycl-type-error-severity
    :initarg :tycl-type-error-severity
    :initform :warn
    :accessor tycl-type-error-severity
    :documentation "Type error handling: :ignore, :warn, or :error")))

(defun resolve-tycl-output-dir (system)
  "Resolve tycl-output-dir to an absolute pathname.
   Relative paths are resolved against the system source directory.
   When tycl-output-dir is nil, falls back to the system source directory."
  (let ((output-dir (tycl-output-dir system)))
    (if output-dir
        (if (uiop:absolute-pathname-p output-dir)
            (uiop:ensure-directory-pathname output-dir)
            (merge-pathnames
             (uiop:ensure-directory-pathname output-dir)
             (asdf:system-source-directory system)))
        (asdf:system-source-directory system))))

;;; ============================================================
;;; Component class
;;; ============================================================

(defclass tycl-file (asdf:cl-source-file)
  ()
  (:documentation "TyCL source file (.tycl). Transpiled to .lisp before compilation."))

(defmethod asdf:source-file-type ((c tycl-file) (s asdf:system))
  "tycl")

;;; ============================================================
;;; Operations
;;; ============================================================

(defclass transpile-tycl-op (asdf:downward-operation)
  ()
  (:documentation "Transpile .tycl files to .lisp in the output directory"))

(defclass copy-source-op (asdf:downward-operation)
  ()
  (:documentation "Copy .lisp source files to the output directory"))

;;; ============================================================
;;; Output files
;;; ============================================================

(defmethod asdf:output-files ((o transpile-tycl-op) (c tycl-file))
  (let* ((system (asdf:component-system c))
         (output-dir (resolve-tycl-output-dir system))
         (source-path (asdf:component-pathname c))
         (relative (enough-namestring source-path
                                      (asdf:system-source-directory system))))
    (values
     (list (merge-pathnames
            (make-pathname :type "lisp" :defaults relative)
            output-dir))
     t)))

(defmethod asdf:output-files ((o copy-source-op) (c asdf:cl-source-file))
  (let* ((system (asdf:component-system c))
         (output-dir (resolve-tycl-output-dir system))
         (source-path (asdf:component-pathname c))
         (relative (enough-namestring source-path
                                      (asdf:system-source-directory system))))
    (values
     (list (merge-pathnames relative output-dir))
     t)))

;;; ============================================================
;;; Dependencies: .tycl files
;;; ============================================================

(defmethod asdf:component-depends-on ((o asdf:compile-op) (c tycl-file))
  `((transpile-tycl-op ,c) ,@(call-next-method)))

(defmethod asdf:component-depends-on ((o asdf:load-source-op) (c tycl-file))
  `((transpile-tycl-op ,c) ,@(call-next-method)))

(defmethod asdf:input-files ((o asdf:compile-op) (c tycl-file))
  (list (first (asdf:output-files (asdf:make-operation 'transpile-tycl-op) c))))

(defmethod asdf:input-files ((o asdf:load-source-op) (c tycl-file))
  (list (first (asdf:output-files (asdf:make-operation 'transpile-tycl-op) c))))

;;; ============================================================
;;; Dependencies: .lisp files in tycl-system
;;; ============================================================

(defmethod asdf:component-depends-on ((o asdf:compile-op) (c asdf:cl-source-file))
  (if (and (typep (asdf:component-system c) 'tycl-system)
           (not (typep c 'tycl-file)))
      `((copy-source-op ,c) ,@(call-next-method))
      (call-next-method)))

(defmethod asdf:component-depends-on ((o asdf:load-source-op) (c asdf:cl-source-file))
  (if (and (typep (asdf:component-system c) 'tycl-system)
           (not (typep c 'tycl-file)))
      `((copy-source-op ,c) ,@(call-next-method))
      (call-next-method)))

(defmethod asdf:input-files ((o asdf:compile-op) (c asdf:cl-source-file))
  (if (and (typep (asdf:component-system c) 'tycl-system)
           (not (typep c 'tycl-file)))
      (list (first (asdf:output-files (asdf:make-operation 'copy-source-op) c)))
      (call-next-method)))

(defmethod asdf:input-files ((o asdf:load-source-op) (c asdf:cl-source-file))
  (if (and (typep (asdf:component-system c) 'tycl-system)
           (not (typep c 'tycl-file)))
      (list (first (asdf:output-files (asdf:make-operation 'copy-source-op) c)))
      (call-next-method)))

;;; ============================================================
;;; Perform
;;; ============================================================

(defmethod asdf:perform ((o transpile-tycl-op) (c tycl-file))
  (let* ((input-file (asdf:component-pathname c))
         (output-file (first (asdf:output-files o c)))
         (system (asdf:component-system c))
         (extract-types (tycl-extract-types-p system))
         (save-types (tycl-save-types-p system)))
    (ensure-directories-exist output-file)
    (tycl:transpile-file input-file output-file
                         :extract-types extract-types
                         :save-types save-types)))

(defmethod asdf:perform ((o copy-source-op) (c asdf:cl-source-file))
  (let* ((input-file (asdf:component-pathname c))
         (output-file (first (asdf:output-files o c))))
    (unless (equal (namestring input-file) (namestring output-file))
      (ensure-directories-exist output-file)
      (uiop:copy-file input-file output-file))))

;;; ============================================================
;;; Rebuild check
;;; ============================================================

(defmethod asdf:operation-done-p ((o transpile-tycl-op) (c tycl-file))
  (let ((source (asdf:component-pathname c))
        (output (first (asdf:output-files o c))))
    (and (probe-file output)
         (>= (file-write-date output)
             (file-write-date source)))))

(defmethod asdf:operation-done-p ((o copy-source-op) (c asdf:cl-source-file))
  (let ((source (asdf:component-pathname c))
        (output (first (asdf:output-files o c))))
    (or (equal source output)
        (and (probe-file output)
             (>= (file-write-date output)
                  (file-write-date source))))))

;;; ============================================================
;;; Register component type
;;; ============================================================

;; ASDF's class-for-type resolves component types by looking up
;; the symbol in *package* and then in :asdf/interface.
;; Import tycl-file into asdf/interface so (:tycl-file "name")
;; works in defsystem forms regardless of *package*.
(dolist (pkg-name '(:asdf/interface :asdf :asdf-user))
  (let ((pkg (find-package pkg-name)))
    (when pkg
      (ignore-errors (import 'tycl-file pkg)))))

;;; ============================================================
;;; Dirty patch: rove compatibility
;;; ============================================================
;;;
;;; Rove discovers test suites by looking up asdf:component-pathname
;;; in its *file-package* hash table. However, the keys in *file-package*
;;; are set from *load-pathname* (.fasl) or *compile-file-pathname* (.lisp)
;;; at load time, which never match the .tycl component pathname.
;;;
;;; This patch registers an additional .tycl -> package mapping in
;;; *file-package* after loading a tycl-file, so rove can find the
;;; test suites. Does nothing when rove is not loaded.
;;;
;;; WARNING: This accesses rove's internal symbol rove/core/suite/file::*file-package*.
;;; If rove changes its internals, a warning will be emitted but the build will not fail.

(defmethod asdf:perform :after ((o asdf:load-op) (c tycl-file))
  (let ((rove-pkg (find-package :rove/core/suite/file)))
    (when rove-pkg
      (handler-case
          (let* ((ht-sym (find-symbol "*FILE-PACKAGE*" rove-pkg))
                 (ht (and ht-sym (boundp ht-sym) (symbol-value ht-sym))))
            (unless (hash-table-p ht)
              (warn "TyCL rove patch: rove's *FILE-PACKAGE* is not a hash-table ~
                     (got ~S). Rove internals may have changed."
                    (type-of ht))
              (return-from asdf:perform))
            (let* ((component-key (uiop:native-namestring
                                   (asdf:component-pathname c)))
                   (lisp-path (first (asdf:output-files
                                      (asdf:make-operation 'transpile-tycl-op) c)))
                   (fasl-path (first (asdf:output-files
                                      (asdf:make-operation 'asdf:compile-op) c)))
                   (mapped-pkg (or (gethash (uiop:native-namestring fasl-path) ht)
                                   (gethash (uiop:native-namestring lisp-path) ht))))
              (cond
                (mapped-pkg
                 (unless (gethash component-key ht)
                   (setf (gethash component-key ht) mapped-pkg)))
                (t
                 (warn "TyCL rove patch: no package mapping found for ~A or ~A. ~
                        Rove may not discover tests in ~A."
                       (uiop:native-namestring fasl-path)
                       (uiop:native-namestring lisp-path)
                       component-key)))))
        (error (e)
          (warn "TyCL rove patch failed for ~A: ~A~%~
                 Rove internals may have changed. Build continues."
                (asdf:component-pathname c) e))))))
