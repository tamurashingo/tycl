;;;; asd-parser-test.lisp
;;;; Tests for LSP ASD parser module

(defpackage :tycl/test/lsp/asd-parser
  (:use :cl :rove))

(in-package :tycl/test/lsp/asd-parser)

;;; ============================================================
;;; Helpers
;;; ============================================================

(defun tycl-root ()
  "Return the root directory of the tycl project"
  (asdf:system-source-directory :tycl))

(defun sample-root ()
  "Return the root directory of the sample project"
  (merge-pathnames "sample/" (tycl-root)))

(defun sample-asd-path ()
  "Return the path to sample-project.asd"
  (merge-pathnames "sample-project.asd" (sample-root)))

(defun sample-math-tycl ()
  "Return the path to sample/src/math.tycl"
  (merge-pathnames "src/math.tycl" (sample-root)))

(defun sample-string-utils-tycl ()
  "Return the path to sample/src/string-utils.tycl"
  (merge-pathnames "src/string-utils.tycl" (sample-root)))

(defun sample-config-lisp ()
  "Return the path to sample/src/config.lisp (not a tycl-file)"
  (merge-pathnames "src/config.lisp" (sample-root)))

;;; ============================================================
;;; find-asd-files tests
;;; ============================================================

(deftest test-find-asd-files-in-sample
  (testing "Finds .asd files in the sample project directory"
    (let ((files (tycl.lsp:find-asd-files (sample-root))))
      (ok (listp files) "Should return a list")
      (ok (>= (length files) 1) "Should find at least one .asd file")
      (ok (every (lambda (f) (string= "asd" (pathname-type f))) files)
          "All files should have .asd extension")
      ;; sample-project.asd should be among them
      (ok (find "sample-project" files
                :key (lambda (f) (pathname-name f))
                :test #'string=)
          "Should find sample-project.asd"))))

(deftest test-find-asd-files-in-tycl-root
  (testing "Finds .asd files in the tycl project root"
    (let ((files (tycl.lsp:find-asd-files (tycl-root))))
      (ok (listp files))
      (ok (>= (length files) 1) "Should find at least tycl.asd")
      (ok (find "tycl" files
                :key (lambda (f) (pathname-name f))
                :test #'string=)
          "Should find tycl.asd"))))

(deftest test-find-asd-files-nonexistent-dir
  (testing "Returns empty list for non-existent directory"
    (let ((files (tycl.lsp:find-asd-files "/tmp/tycl-nonexistent-dir-12345/")))
      (ok (null files) "Should return empty list"))))

(deftest test-find-asd-files-no-asd
  (testing "Returns empty list for directory with no .asd files"
    (let ((files (tycl.lsp:find-asd-files (merge-pathnames "src/" (tycl-root)))))
      (ok (null files) "src/ directory should have no .asd files"))))

;;; ============================================================
;;; load-asd-file tests
;;; ============================================================

(deftest test-load-asd-file-sample
  (testing "Loads sample-project.asd and finds tycl-systems"
    (let ((systems (tycl.lsp:load-asd-file (sample-asd-path))))
      (ok (listp systems) "Should return a list")
      (ok (>= (length systems) 1) "Should find at least one tycl-system")
      ;; Each entry should be (name . system)
      (dolist (entry systems)
        (ok (stringp (car entry)) "Key should be a system name string")
        (ok (typep (cdr entry) 'tycl/asdf:tycl-system)
            "Value should be a tycl-system instance"))
      ;; sample-project should be found
      (ok (find "sample-project" systems
                :key #'car :test #'string=)
          "Should find sample-project system"))))

(deftest test-load-asd-file-nonexistent
  (testing "Returns nil for non-existent .asd file"
    (let ((systems (tycl.lsp:load-asd-file "/tmp/nonexistent-12345.asd")))
      (ok (null systems) "Should return nil for missing .asd file"))))

;;; ============================================================
;;; find-system-for-file tests
;;; ============================================================

(deftest test-find-system-for-tycl-file
  (testing "Finds the correct system for a .tycl file"
    (let ((systems (tycl.lsp:load-asd-file (sample-asd-path))))
      (let ((system (tycl.lsp:find-system-for-file (sample-math-tycl) systems)))
        (ok system "Should find a system for math.tycl")
        (ok (typep system 'tycl/asdf:tycl-system)
            "Should be a tycl-system")))))

(deftest test-find-system-for-another-tycl-file
  (testing "Finds system for string-utils.tycl"
    (let ((systems (tycl.lsp:load-asd-file (sample-asd-path))))
      (let ((system (tycl.lsp:find-system-for-file
                     (sample-string-utils-tycl) systems)))
        (ok system "Should find a system for string-utils.tycl")))))

(deftest test-find-system-for-unknown-file
  (testing "Returns nil for a file not in any system"
    (let ((systems (tycl.lsp:load-asd-file (sample-asd-path))))
      (let ((system (tycl.lsp:find-system-for-file
                     #p"/tmp/unknown-file.tycl" systems)))
        (ok (null system) "Should return nil for unknown file")))))

(deftest test-find-system-for-empty-systems
  (testing "Returns nil when systems list is empty"
    (let ((system (tycl.lsp:find-system-for-file (sample-math-tycl) nil)))
      (ok (null system) "Should return nil with empty systems list"))))

;;; ============================================================
;;; resolve-output-path tests
;;; ============================================================

(deftest test-resolve-output-path-with-system
  (testing "Resolves output path using system's tycl-output-dir"
    (let* ((systems (tycl.lsp:load-asd-file (sample-asd-path)))
           (system (tycl.lsp:find-system-for-file (sample-math-tycl) systems)))
      (when system
        (let ((lisp-path (tycl.lsp:resolve-output-path (sample-math-tycl) system)))
          (ok lisp-path "Should return a .lisp path")
          (ok (string= "lisp" (pathname-type lisp-path))
              ".lisp extension for output")
          ;; sample-project has :tycl-output-dir "build/"
          ;; so the lisp output should go to build/
          (let ((dir-components (pathname-directory lisp-path)))
            (ok (member "build" dir-components :test #'equal)
                "Output .lisp should be under build/ directory")))))))

(deftest test-resolve-output-path-without-system
  (testing "Falls back to source directory when system is nil"
    (let* ((file-path (sample-math-tycl)))
      (let ((lisp-path (tycl.lsp:resolve-output-path file-path nil)))
        (ok lisp-path "Should return a .lisp path")
        (ok (string= "lisp" (pathname-type lisp-path)))
        ;; Without a system, output goes next to source
        (ok (equal (pathname-directory lisp-path)
                   (pathname-directory file-path))
            ".lisp should be in same directory as source")))))

;;; ============================================================
;;; load-and-cache-asd-files tests
;;; ============================================================

(deftest test-load-and-cache-asd-files
  (testing "Caches .asd files and systems from workspace root"
    (let ((tycl.lsp::*cached-asd-files* nil)
          (tycl.lsp::*cached-asd-systems* nil))
      (let ((result (tycl.lsp:load-and-cache-asd-files (sample-root))))
        (ok (listp result) "Should return a list")
        (ok (>= (length result) 1) "Should find at least one system")
        ;; Check that cache variables are updated
        (ok (>= (length tycl.lsp:*cached-asd-files*) 1)
            "Should cache .asd files")
        (ok (>= (length tycl.lsp:*cached-asd-systems*) 1)
            "Should cache systems")))))

(deftest test-load-and-cache-resets-previous
  (testing "Reloading resets the previous cache"
    (let ((tycl.lsp::*cached-asd-files* '(#p"/fake/old.asd"))
          (tycl.lsp::*cached-asd-systems* '(("old" . nil))))
      (tycl.lsp:load-and-cache-asd-files (sample-root))
      ;; Old entries should be gone
      (ok (not (find #p"/fake/old.asd" tycl.lsp:*cached-asd-files*
                     :test #'equal))
          "Old cached files should be cleared")
      (ok (not (find "old" tycl.lsp:*cached-asd-systems*
                     :key #'car :test #'string=))
          "Old cached systems should be cleared"))))

;;; ============================================================
;;; transpile-tycl-file tests
;;; ============================================================

(deftest test-transpile-tycl-file-with-cache
  (testing "Transpiles a .tycl file and returns the tycl-types.tmp path"
    ;; Set up cache from sample project
    (let ((tycl.lsp::*cached-asd-files* nil)
          (tycl.lsp::*cached-asd-systems* nil))
      (tycl.lsp:load-and-cache-asd-files (sample-root))
      (let ((result (tycl.lsp:transpile-tycl-file (sample-math-tycl))))
        (ok result "Should return a path on success")
        (ok (string= "tycl-types" (pathname-name result))
            "Should return a tycl-types.tmp path")
        (ok (string= "tmp" (pathname-type result))
            "Should have .tmp extension")
        (ok (probe-file result)
            "Generated tycl-types.tmp file should exist")))))

(deftest test-transpile-tycl-file-without-cache
  (testing "Transpiles even without cached systems (fallback to source dir)"
    (let ((tycl.lsp::*cached-asd-files* nil)
          (tycl.lsp::*cached-asd-systems* nil))
      (let ((result (tycl.lsp:transpile-tycl-file (sample-math-tycl))))
        (ok result "Should still succeed without cache")
        (ok (string= "tycl-types" (pathname-name result))
            "Should return a tycl-types.tmp path")))))

(deftest test-transpile-tycl-file-nonexistent
  (testing "Returns nil for non-existent file"
    (let ((tycl.lsp::*cached-asd-files* nil)
          (tycl.lsp::*cached-asd-systems* nil))
      (let ((result (tycl.lsp:transpile-tycl-file #p"/tmp/nonexistent-12345.tycl")))
        (ok (null result) "Should return nil for missing file")))))

;;; ============================================================
;;; transpile-all-in-asd tests
;;; ============================================================

(deftest test-transpile-all-in-asd
  (testing "Transpiles all tycl-file components in the .asd"
    (let ((count (tycl.lsp:transpile-all-in-asd (sample-asd-path))))
      (ok (integerp count) "Should return a count")
      (ok (>= count 3)
          "Should transpile at least 3 files (math, string-utils, main in sample-project)"))))

(deftest test-transpile-all-in-asd-nonexistent
  (testing "Returns 0 for non-existent .asd file"
    (let ((count (tycl.lsp:transpile-all-in-asd "/tmp/nonexistent-12345.asd")))
      (ok (= count 0) "Should transpile 0 files"))))

;;; ============================================================
;;; component-matches-file-p tests (internal)
;;; ============================================================

(deftest test-component-matches-file-p
  (testing "Correctly matches component pathname to file path"
    (let* ((systems (tycl.lsp:load-asd-file (sample-asd-path)))
           (system (cdr (find "sample-project" systems
                              :key #'car :test #'string=))))
      (when system
        ;; Walk to find the math component
        (let ((math-component (tycl.lsp::walk-components system (sample-math-tycl))))
          (ok math-component "Should find math component")
          (ok (typep math-component 'tycl/asdf:tycl-file)
              "Math component should be a tycl-file"))))))

(deftest test-walk-components-no-match
  (testing "walk-components returns nil for non-matching path"
    (let* ((systems (tycl.lsp:load-asd-file (sample-asd-path)))
           (system (cdr (find "sample-project" systems
                              :key #'car :test #'string=))))
      (when system
        (let ((result (tycl.lsp::walk-components system #p"/tmp/no-such-file.tycl")))
          (ok (null result) "Should return nil for non-matching path"))))))
