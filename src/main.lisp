;;;; TyCL Main Package
;;;; Entry point for TyCL transpiler and type checker

(in-package #:tycl)

(defun load-tycl-hooks (&optional (base-dir "."))
  "Load tycl-hooks.lisp from the specified directory if it exists.
   This allows users to register custom type extractors for their macros.
   
   The file is searched in:
     1. base-dir/tycl-hooks.lisp
     2. ./tycl-hooks.lisp (if base-dir is not current dir)
   
   Returns T if hooks were loaded, NIL otherwise.
   Prevents loading the same file multiple times."
  (let* ((hook-filename "tycl-hooks.lisp")
         (candidates (list (merge-pathnames hook-filename base-dir)
                          (when (not (equal base-dir "."))
                            (merge-pathnames hook-filename ".")))))
    (dolist (hook-path candidates)
      (when (and hook-path (probe-file hook-path))
        (load-hook-configuration hook-path)
        (return-from load-tycl-hooks t)))
    nil))

(defun load-tycl (tycl-file &key 
                             (output-dir nil)
                             (if-exists :error)
                             (compile nil)
                             (verbose t)
                             (print nil)
                             (extract-types t)
                             (save-types t)
                             (json-output nil))
  "Load a .tycl file by transpiling it and loading into the current REPL.
   
   Parameters:
     tycl-file  - Path to the .tycl file
     :output-dir - Directory for the generated .lisp file (default: same as .tycl file)
     :if-exists - Action when .lisp file already exists
                  :error     - Signal an error (default)
                  :overwrite - Overwrite the existing file
     :compile   - If T, compile the generated .lisp file before loading (default NIL)
     :verbose   - If T, print progress messages (default T)
     :print     - If T, print each form as it's loaded (default NIL)
     :extract-types - If T, extract type information during transpilation (default T)
     :save-types    - If T, save type information to .tycl-types file (default T)
     :json-output   - If T, also save type information to .tycl-types.json file (default NIL)
   
   Returns the pathname of the loaded file.
   
   Note: Automatically loads tycl-hooks.lisp if present in the source directory.
   
   Examples:
     (tycl:load-tycl \"src/example.tycl\")
       => Transpiles to src/example.lisp
     
     (tycl:load-tycl \"src/example.tycl\" :output-dir \"build\")
       => Transpiles to build/example.lisp
     
     (tycl:load-tycl \"src/example.tycl\" :if-exists :overwrite)
       => Overwrites existing src/example.lisp
     
     (tycl:load-tycl \"src/example.tycl\" :json-output t)
       => Also generates src/example.tycl-types.json"
  (let* ((tycl-path (pathname tycl-file))
         (source-dir (or (directory-namestring tycl-path) "."))
         (lisp-path (if output-dir
                        (make-pathname :name (pathname-name tycl-path)
                                       :type "lisp"
                                       :directory (pathname-directory 
                                                   (pathname output-dir)))
                        (make-pathname :type "lisp" :defaults tycl-path))))
    
    ;; Load hooks from source directory if available
    (when (and source-dir (not (string= source-dir "")))
      (load-tycl-hooks source-dir))
    
    ;; Check if .lisp file already exists
    (when (and (probe-file lisp-path)
               (eq if-exists :error))
      (error "Generated file already exists: ~A~%~
              Use :if-exists :overwrite to force regeneration, or delete the file manually."
             lisp-path))
    
    ;; Transpile .tycl -> .lisp
    (when verbose
      (format t "~&; Transpiling ~A -> ~A...~%" tycl-file lisp-path))
    (transpile-file tycl-path lisp-path 
                    :extract-types extract-types
                    :save-types save-types)
    
    ;; Save JSON format if requested
    (when (and save-types json-output)
      (let ((json-path (make-pathname :type "tycl-types.json" :defaults lisp-path)))
        (when verbose
          (format t "~&; Saving type information to ~A...~%" json-path))
        (save-type-database-json json-path)))
    
    ;; Load or compile-and-load
    (if compile
        (progn
          (when verbose
            (format t "~&; Compiling ~A...~%" lisp-path))
          (compile-file lisp-path :verbose verbose :print print)
          (when verbose
            (format t "~&; Loading compiled file...~%"))
          (load (compile-file-pathname lisp-path) :verbose verbose :print print))
        (progn
          (when verbose
            (format t "~&; Loading ~A...~%" lisp-path))
          (load lisp-path :verbose verbose :print print)))
    
    (when verbose
      (format t "~&; Loaded ~A~%" tycl-file))
    
    tycl-path))

(defun compile-and-load-tycl (tycl-file &key 
                                        (output-dir nil)
                                        (if-exists :error)
                                        (verbose t)
                                        (print nil)
                                        (extract-types t)
                                        (save-types t)
                                        (json-output nil))
  "Convenience function: transpile, compile, and load a .tycl file.
   
   Equivalent to (load-tycl tycl-file :compile t ...)"
  (load-tycl tycl-file 
             :output-dir output-dir
             :if-exists if-exists
             :compile t 
             :verbose verbose 
             :print print
             :extract-types extract-types
             :save-types save-types
             :json-output json-output))

;; Package is ready
(format *error-output* "~&TyCL transpiler loaded.~%")
(format *error-output* "~&  Use (tycl:load-tycl \"file.tycl\") to load TyCL files.~%")
