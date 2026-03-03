;;;; ASD Parser for LSP
;;;; Parses .asd files to find tycl-system definitions and resolve output paths

(in-package :tycl.lsp)

;;; ============================================================
;;; .asd file cache
;;; ============================================================

(defvar *cached-asd-files* nil
  "List of .asd file pathnames found in the workspace root")

(defvar *cached-asd-systems* nil
  "List of (system-name . system) pairs for tycl-system instances loaded from .asd files")

;;; ============================================================
;;; Finding .asd files
;;; ============================================================

(defun find-asd-files (root-path)
  "Find .asd files directly under ROOT-PATH (not recursive).
   Returns a list of pathnames."
  (let ((dir (uiop:ensure-directory-pathname root-path)))
    (remove-if-not
     (lambda (f) (string= (pathname-type f) "asd"))
     (uiop:directory-files dir))))

;;; ============================================================
;;; Loading .asd files
;;; ============================================================

(defun load-asd-file (asd-path)
  "Load a .asd file via asdf:load-asd and return the list of
   tycl-system instances that were registered.
   Returns a list of (system-name . system-object) pairs."
  (when *debug-mode*
    (format *error-output* "~%[ASD] Loading: ~A~%" asd-path))
  (handler-case
      (progn
        (asdf:load-asd asd-path)
        ;; Collect tycl-system instances that were defined in this .asd
        ;; We check all registered systems and filter by source-file
        (let ((results nil)
              (asd-truename (truename asd-path)))
          (asdf:map-systems
           (lambda (system)
             (when (typep system 'tycl/asdf:tycl-system)
               (let ((sys-source (asdf:system-source-file system)))
                 (when (and sys-source
                            (equal (truename sys-source) asd-truename))
                   (push (cons (asdf:component-name system) system) results))))))
          (when *debug-mode*
            (format *error-output* "~%[ASD] Found ~D tycl-system(s) in ~A~%"
                    (length results) asd-path))
          results))
    (error (e)
      (when *debug-mode*
        (format *error-output* "~%[ASD] Error loading ~A: ~A~%" asd-path e))
      nil)))

;;; ============================================================
;;; Finding the system for a given file
;;; ============================================================

(defun component-matches-file-p (component file-path)
  "Check if COMPONENT's pathname matches FILE-PATH."
  (let ((comp-path (asdf:component-pathname component)))
    (when comp-path
      (handler-case
          (equal (truename comp-path) (truename file-path))
        ;; truename can fail if the file doesn't exist yet
        (error ()
          (equal (namestring comp-path) (namestring file-path)))))))

(defun walk-components (component file-path)
  "Recursively walk COMPONENT's children to find a tycl-file matching FILE-PATH.
   Returns the matching component or NIL."
  (cond
    ;; Leaf component: check if it matches
    ((typep component 'tycl/asdf:tycl-file)
     (when (component-matches-file-p component file-path)
       component))
    ;; Module: recurse into children
    ((typep component 'asdf:module)
     (dolist (child (asdf:component-children component))
       (let ((match (walk-components child file-path)))
         (when match
           (return match)))))
    (t nil)))

(defun find-system-for-file (file-path asd-systems)
  "Find the tycl-system that contains FILE-PATH as a tycl-file component.
   ASD-SYSTEMS is a list of (name . system) pairs.
   Returns the matching system or NIL."
  (dolist (entry asd-systems)
    (let* ((system (cdr entry))
           (match (walk-components system file-path)))
      (when match
        (when *debug-mode*
          (format *error-output* "~%[ASD] File ~A belongs to system ~A~%"
                  file-path (car entry)))
        (return system)))))

;;; ============================================================
;;; Resolving output paths
;;; ============================================================

(defun resolve-output-path (file-path system)
  "Determine the output path for a transpiled .tycl file.
   If SYSTEM is non-NIL, use its tycl-output-dir to compute the path.
   If SYSTEM is NIL, output to the same directory as the source file.
   Returns the .lisp output path."
  (if system
      (let* ((output-dir (tycl/asdf::resolve-tycl-output-dir system))
             (source-dir (asdf:system-source-directory system))
             (relative (enough-namestring file-path source-dir)))
        (if output-dir
            (merge-pathnames
             (make-pathname :type "lisp" :defaults relative)
             output-dir)
            (make-pathname :type "lisp" :defaults file-path)))
      ;; No system found: output in same directory as source
      (make-pathname :type "lisp" :defaults file-path)))

;;; ============================================================
;;; Cache management
;;; ============================================================

(defun load-and-cache-asd-files (root-path)
  "Find and load all .asd files under ROOT-PATH, caching the results.
   Returns the list of (name . system) pairs."
  (setf *cached-asd-files* (find-asd-files root-path))
  (setf *cached-asd-systems* nil)
  (when *debug-mode*
    (format *error-output* "~%[ASD] Found ~D .asd file(s) in ~A~%"
            (length *cached-asd-files*) root-path))
  (dolist (asd-file *cached-asd-files*)
    (let ((systems (load-asd-file asd-file)))
      (setf *cached-asd-systems* (append *cached-asd-systems* systems))))
  (when *debug-mode*
    (format *error-output* "~%[ASD] Total cached tycl-system(s): ~D~%"
            (length *cached-asd-systems*)))
  *cached-asd-systems*)

;;; ============================================================
;;; Transpiling on save
;;; ============================================================

(defun transpile-tycl-file (file-path)
  "Transpile a single .tycl file using the cached .asd information.
   Saves project-level tycl-types.tmp in the current directory.
   Returns the tycl-types.tmp path on success, or NIL on failure."
  (let ((system (find-system-for-file file-path *cached-asd-systems*)))
    (let ((lisp-path (resolve-output-path file-path system)))
      (when *debug-mode*
        (format *error-output* "~%[ASD] Transpiling ~A -> ~A~%" file-path lisp-path))
      (handler-case
          (progn
            (ensure-directories-exist lisp-path)
            (tycl:transpile-file file-path lisp-path
                                 :extract-types t
                                 :save-types nil
                                 :output *error-output*)
            ;; Save project-level type info
            (let ((project-types (make-pathname :name "tycl-types" :type "tmp"
                                                :defaults *default-pathname-defaults*)))
              (tycl:save-project-types project-types :output *error-output*)
              (when *debug-mode*
                (format *error-output* "~%[ASD] Generated project types: ~A~%" project-types))
              project-types))
        (error (e)
          (when *debug-mode*
            (format *error-output* "~%[ASD] Transpile error for ~A: ~A~%"
                    file-path e))
          nil)))))

;;; ============================================================
;;; Transpile all files in .asd
;;; ============================================================

(defun transpile-all-in-asd (asd-path &key load-dependencies (output *standard-output*))
  "Load a .asd file and transpile all tycl-file components in all tycl-systems.
   If LOAD-DEPENDENCIES is T, load each system's :depends-on systems before transpiling.
   OUTPUT is the stream for progress messages (default: *standard-output*).
   Saves project-level tycl-types.tmp next to the .asd file after all files are transpiled.
   Returns the number of files transpiled."
  (let ((systems (load-asd-file asd-path))
        (count 0))
    (dolist (entry systems)
      (let ((system (cdr entry)))
        (when load-dependencies
          (dolist (dep (asdf:system-depends-on system))
            (handler-case
                (asdf:load-system dep)
              (error (e)
                (format output "~&Warning: Failed to load dependency ~A: ~A~%" dep e)))))
        (labels ((process-component (component)
                   (cond
                     ((typep component 'tycl/asdf:tycl-file)
                      (let* ((input (asdf:component-pathname component))
                             (output-dir (tycl/asdf::resolve-tycl-output-dir system))
                             (source-dir (asdf:system-source-directory system))
                             (relative (enough-namestring input source-dir))
                             (lisp-output (if output-dir
                                              (merge-pathnames
                                               (make-pathname :type "lisp" :defaults relative)
                                               output-dir)
                                              (make-pathname :type "lisp" :defaults input))))
                        (format output "~&Transpiling ~A -> ~A~%" input lisp-output)
                        (handler-case
                            (progn
                              (ensure-directories-exist lisp-output)
                              (tycl:transpile-file input lisp-output
                                                   :extract-types t
                                                   :save-types nil
                                                   :output output)
                              (incf count))
                          (error (e)
                            (format output "~&Error transpiling ~A: ~A~%" input e)))))
                     ((typep component 'asdf:module)
                      (dolist (child (asdf:component-children component))
                        (process-component child))))))
          (process-component system))))
    ;; Save project-level type information next to the .asd file
    (when (> count 0)
      (let ((project-types (tycl:generate-project-type-file-path asd-path)))
        (tycl:save-project-types project-types :output output)))
    count))

;;; ============================================================
;;; Check all files in .asd
;;; ============================================================

(defun check-all-in-asd (asd-path &key load-dependencies (output *standard-output*))
  "Load a .asd file and type-check all tycl-file components in all tycl-systems.
   If LOAD-DEPENDENCIES is T, load each system's :depends-on systems before checking.
   OUTPUT is the stream for progress messages (default: *standard-output*).
   Loads project-level tycl-types.tmp before checking so all type info is available.
   Returns two values: the number of files checked and the number of files with errors."
  ;; Load project type information before checking
  (let ((project-types (tycl:generate-project-type-file-path asd-path)))
    (when (probe-file project-types)
      (handler-case
          (tycl:load-type-database project-types :output output)
        (error (e)
          (format output "~&Warning: Failed to load project types from ~A: ~A~%"
                  project-types e)))))
  (let ((systems (load-asd-file asd-path))
        (checked 0)
        (failed 0))
    (dolist (entry systems)
      (let ((system (cdr entry)))
        ;; Load dependency systems if requested
        (when load-dependencies
          (dolist (dep (asdf:system-depends-on system))
            (handler-case
                (asdf:load-system dep)
              (error (e)
                (format output "~&Warning: Failed to load dependency ~A: ~A~%" dep e)))))
        (labels ((process-component (component)
                   (cond
                     ((typep component 'tycl/asdf:tycl-file)
                      (let ((input (asdf:component-pathname component)))
                        (format output "~&Checking ~A~%" input)
                        (handler-case
                            (progn
                              (incf checked)
                              (unless (tycl:check-file input)
                                (incf failed)))
                          (error (e)
                            (format output "~&Error checking ~A: ~A~%" input e)
                            (incf checked)
                            (incf failed)))))
                     ((typep component 'asdf:module)
                      (dolist (child (asdf:component-children component))
                        (process-component child))))))
          (process-component system))))
    (values checked failed)))
