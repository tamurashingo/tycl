;;;; TyCL Declaration Files
;;;; Load type declarations for external libraries (.d.tycl files)
;;;; Similar to TypeScript's .d.ts files

(in-package #:tycl)

;;; Configuration

(defvar *declaration-search-paths*
  (list (merge-pathnames
         (make-pathname :directory '(:relative ".config" "tycl" "declarations"))
         (user-homedir-pathname)))
  "List of directories to search for .d.tycl declaration files.
   Project-local paths are added dynamically during transpilation.")

(defvar *loaded-declaration-files* nil
  "List of declaration files that have been loaded (to avoid duplicate loading)")

;;; Core Loading

(defun load-declaration-file (file &key (output *error-output*))
  "Load type declarations from a .d.tycl file.
   Reads the file using TyCL reader and extracts type information only.
   No transpilation or code generation occurs.
   Returns T if loaded successfully, NIL otherwise."
  (let ((path (probe-file file)))
    (cond
      ((not path)
       (when output
         (warn "Declaration file not found: ~A" file))
       nil)
      ((member path *loaded-declaration-files* :test #'equal)
       ;; Already loaded
       t)
      (t
       (handler-case
           (let ((*readtable* tycl/reader:*tycl-readtable*)
                 (*package* *package*)
                 (*current-file* (namestring path))
                 (*current-package* "COMMON-LISP-USER"))
             (with-open-file (in path :direction :input)
               (loop for form = (read in nil :eof)
                     until (eq form :eof)
                     do ;; Extract type information only.
                        ;; Do NOT call process-reader-package-form here:
                        ;; Declaration files reference external packages that may not
                        ;; exist as Lisp packages. Changing *package* to such a package
                        ;; would cause CL symbols (DEFUN, DEFVAR, etc.) to be interned
                        ;; in the wrong package, breaking eq comparisons in
                        ;; extract-type-from-form. Instead, only update *current-package*
                        ;; (via extract-type-from-form's in-package handler) for type
                        ;; registration purposes.
                        (extract-type-from-form form)))
             (push path *loaded-declaration-files*)
             (when output
               (format output "~&; Loaded declarations from ~A~%" path))
             t)
         (error (e)
           (warn "Failed to load declaration file ~A: ~A" path e)
           nil))))))

(defun load-declarations-directory (directory &key (output *error-output*))
  "Load all .d.tycl files from a directory.
   Returns the number of files successfully loaded."
  (let ((dir (uiop:ensure-directory-pathname directory))
        (count 0))
    (when (uiop:directory-exists-p dir)
      (let ((files (directory (merge-pathnames "*.d.tycl" dir))))
        (dolist (file files)
          (when (load-declaration-file file :output output)
            (incf count)))))
    count))

(defun find-and-load-declarations (directory &key (output *error-output*))
  "Find and load declaration files from standard locations.
   Searches:
     1. <directory>/tycl-declarations/  (project-local)
     2. Each path in *declaration-search-paths* (user-global)
   Returns the total number of files loaded."
  (let ((total 0)
        (project-dir (merge-pathnames
                      (make-pathname :directory '(:relative "tycl-declarations"))
                      (uiop:ensure-directory-pathname directory))))
    ;; 1. Project-local declarations
    (incf total (load-declarations-directory project-dir :output output))
    ;; 2. User-global declarations
    (dolist (search-path *declaration-search-paths*)
      (incf total (load-declarations-directory search-path :output output)))
    total))

(defun clear-loaded-declarations ()
  "Clear the list of loaded declaration files.
   Useful for testing or reloading declarations."
  (setf *loaded-declaration-files* nil))
