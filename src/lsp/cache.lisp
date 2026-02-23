(in-package :tycl.lsp)

;;; Type Information Cache

(defvar *type-info-cache* (make-hash-table :test 'equal)
  "Global cache for type information. Key: package name, Value: package symbols hash")

(defvar *workspace-root* nil
  "Root directory of the workspace")

(defstruct type-info
  kind        ; :function, :value, :class, :method
  name        ; symbol name
  type-spec   ; type specification
  location)   ; file location (filename . line-number)

(defun clear-cache ()
  "Clear all type information cache"
  (clrhash *type-info-cache*))

(defun find-tycl-types-files (directory)
  "Find all .tycl-types files in directory recursively"
  (when (probe-file directory)
    (let ((files '()))
      (labels ((scan-dir (dir)
                 (dolist (entry (uiop:directory-files dir))
                   (when (string= (pathname-type entry) "tycl-types")
                     (push entry files)))
                 (dolist (subdir (uiop:subdirectories dir))
                   (scan-dir subdir))))
        (scan-dir (uiop:ensure-directory-pathname directory)))
      files)))

(defun load-type-info-file (filepath)
  "Load type information from a .tycl-types file"
  (when (probe-file filepath)
    (with-open-file (stream filepath :direction :input)
      (let ((data (read stream nil nil)))
        (when data
          (dolist (entry data)
            (let* ((package-name (getf entry :package))
                   (package-table (or (gethash package-name *type-info-cache*)
                                     (setf (gethash package-name *type-info-cache*)
                                           (make-hash-table :test 'equal)))))
              (dolist (symbol-info (getf entry :symbols))
                (let* ((symbol-name (getf symbol-info :name))
                       (info (make-type-info
                              :kind (getf symbol-info :kind)
                              :name symbol-name
                              :type-spec (getf symbol-info :type)
                              :location (cons (namestring filepath)
                                            (getf symbol-info :line)))))
                  (setf (gethash symbol-name package-table) info))))))))))

(defun load-workspace-types (root-path)
  "Load all type information from workspace"
  (setf *workspace-root* root-path)
  (clear-cache)
  (let ((files (find-tycl-types-files root-path)))
    (dolist (file files)
      (handler-case
          (load-type-info-file file)
        (error (e)
          (when *debug-mode*
            (format *error-output* "~%Error loading ~A: ~A~%" file e)))))))

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
