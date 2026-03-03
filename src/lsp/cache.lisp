(in-package :tycl.lsp)

;;; Type Information Cache

(defvar *type-info-cache* (make-hash-table :test 'equal)
  "Global cache for type information. Key: package name, Value: package symbols hash")

(defvar *workspace-root* nil
  "Root directory of the workspace")

(defstruct type-info
  kind        ; :function, :value, :class, :method, :type-alias
  name        ; symbol name
  type-spec   ; type specification
  type-params ; list of type parameter names for parametric aliases
  location)   ; file location (filename . line-number)

(defun clear-cache ()
  "Clear all type information cache"
  (clrhash *type-info-cache*))

(defun find-tycl-types-files (directory)
  "Find all tycl-types.tmp files in directory recursively"
  (when (probe-file directory)
    (let ((files '()))
      (labels ((scan-dir (dir)
                 (dolist (entry (uiop:directory-files dir))
                   (when (and (string= (pathname-name entry) "tycl-types")
                              (string= (pathname-type entry) "tmp"))
                     (push entry files)))
                 (dolist (subdir (uiop:subdirectories dir))
                   (scan-dir subdir))))
        (scan-dir (uiop:ensure-directory-pathname directory)))
      files)))

(defun load-type-info-file (filepath)
  "Load type information from a tycl-types.tmp file (supports multiple S-expressions)"
  (when (probe-file filepath)
    (when *debug-mode*
      (format *error-output* "~%[Cache]   Reading file: ~A~%" filepath))
    (with-open-file (stream filepath :direction :input)
      (loop for data = (read stream nil nil)
            while data
            do (progn
                 (when *debug-mode*
                   (format *error-output* "~%[Cache]   Data format: ~A~%" (if data (car data) "NIL")))
                 (when (eq (car data) :tycl-type-database)
                   (let ((entries (getf (cdr data) :entries))
                         (package-name (getf (cdr data) :package)))
                     (when *debug-mode*
                       (format *error-output* "~%[Cache]   Package: ~A~%" package-name)
                       (format *error-output* "~%[Cache]   Entries count: ~D~%" (length entries)))
                     (let ((package-table (or (gethash package-name *type-info-cache*)
                                             (setf (gethash package-name *type-info-cache*)
                                                   (make-hash-table :test 'equal)))))
                       (dolist (entry entries)
                         (let* ((kind (first entry))
                                (props (rest entry))
                                (symbol-name (getf props :symbol)))
                           (when symbol-name
                             (let ((info (make-type-info
                                          :kind kind
                                          :name symbol-name
                                          :type-spec (case kind
                                                      (:function
                                                       (list :function
                                                             (getf props :params)
                                                             (getf props :return)))
                                                      (:method
                                                       (list :function
                                                             (getf props :params)
                                                             (getf props :return)))
                                                      (:value
                                                       (getf props :type))
                                                      (:class
                                                       (list :class
                                                             (getf props :slots)
                                                             (getf props :superclasses)))
                                                      (:type-alias
                                                       (getf props :expanded-type)))
                                          :type-params (when (eq kind :type-alias)
                                                         (getf props :type-params))
                                          :location (cons (namestring filepath) 0))))
                               (when *debug-mode*
                                 (format *error-output* "~%[Cache]     Symbol: ~A (~A) type-spec: ~A~%"
                                         symbol-name kind (type-info-type-spec info)))
                               (setf (gethash symbol-name package-table) info)))))))))))))

(defun load-workspace-types (root-path)
  "Load all type information from workspace (reads tycl-types.tmp files)"
  (when *debug-mode*
    (format *error-output* "~%[Cache] Loading workspace types from: ~A~%" root-path))
  (setf *workspace-root* root-path)
  (clear-cache)
  (let ((files (find-tycl-types-files root-path)))
    (when *debug-mode*
      (format *error-output* "~%[Cache] Found ~D tycl-types.tmp files~%" (length files))
      (dolist (file files)
        (format *error-output* "~%[Cache]   - ~A~%" file)))
    (dolist (file files)
      (handler-case
          (progn
            (when *debug-mode*
              (format *error-output* "~%[Cache] Loading ~A...~%" file))
            (load-type-info-file file)
            (when *debug-mode*
              (format *error-output* "~%[Cache] Successfully loaded ~A~%" file)))
        (error (e)
          (when *debug-mode*
            (format *error-output* "~%[Cache] Error loading ~A: ~A~%" file e))))))
  (when *debug-mode*
    (format *error-output* "~%[Cache] Total symbols loaded: ~D~%"
            (length (get-all-symbols)))))

(defun query-type-info (symbol-name &optional package-name)
  "Query type information for a symbol"
  (if package-name
      (let ((package-table (gethash package-name *type-info-cache*)))
        (when package-table
          (gethash symbol-name package-table)))
      ;; Search all packages
      (loop for package-table being the hash-values of *type-info-cache*
            for info = (gethash symbol-name package-table)
            when info return info)))

(defun get-all-symbols (&optional package-name)
  "Get all symbols in cache, optionally filtered by package"
  (let ((symbols '()))
    (if package-name
        (let ((package-table (gethash package-name *type-info-cache*)))
          (when package-table
            (maphash (lambda (name info)
                      (declare (ignore name))
                      (push info symbols))
                    package-table)))
        (maphash (lambda (pkg-name package-table)
                  (declare (ignore pkg-name))
                  (maphash (lambda (name info)
                            (declare (ignore name))
                            (push info symbols))
                          package-table))
                *type-info-cache*))
    symbols))
