;;;; Tests for TyCL ASDF Extension

(defpackage #:tycl/test/asdf
  (:use #:cl #:rove))

(in-package #:tycl/test/asdf)

;;; Helper to create a minimal tycl-system instance for testing
(defun make-test-system (&key (output-dir nil) (extract-types t) (save-types t)
                              (type-error-severity :warn))
  (let* ((tycl-system (asdf:find-system :tycl))
         (source-dir (asdf:system-source-directory tycl-system))
         (system (make-instance 'tycl/asdf:tycl-system
                                :name "test-system"
                                :source-file (asdf:system-source-file tycl-system)
                                :tycl-output-dir output-dir
                                :tycl-extract-types extract-types
                                :tycl-save-types save-types
                                :tycl-type-error-severity type-error-severity)))
    ;; Ensure system-source-directory works by setting absolute-pathname
    (setf (slot-value system 'asdf/component:absolute-pathname) source-dir)
    system))

(deftest test-tycl-system-defaults
  (testing "tycl-system class has correct default slot values"
    (let ((system (make-instance 'tycl/asdf:tycl-system :name "defaults-test")))
      (ok (null (tycl/asdf::tycl-output-dir system)))
      (ok (eq t (tycl/asdf::tycl-extract-types-p system)))
      (ok (eq t (tycl/asdf::tycl-save-types-p system)))
      (ok (eq :warn (tycl/asdf::tycl-type-error-severity system))))))

(deftest test-tycl-system-custom-values
  (testing "tycl-system class accepts custom slot values"
    (let ((system (make-instance 'tycl/asdf:tycl-system
                                 :name "custom-test"
                                 :tycl-output-dir "build/"
                                 :tycl-extract-types nil
                                 :tycl-save-types nil
                                 :tycl-type-error-severity :error)))
      (ok (equal "build/" (tycl/asdf::tycl-output-dir system)))
      (ok (null (tycl/asdf::tycl-extract-types-p system)))
      (ok (null (tycl/asdf::tycl-save-types-p system)))
      (ok (eq :error (tycl/asdf::tycl-type-error-severity system))))))

(deftest test-resolve-tycl-output-dir-nil
  (testing "resolve-tycl-output-dir returns nil when output-dir is not set"
    (let ((system (make-instance 'tycl/asdf:tycl-system :name "nil-dir-test")))
      (ok (null (tycl/asdf::resolve-tycl-output-dir system))))))

(deftest test-resolve-tycl-output-dir-relative
  (testing "resolve-tycl-output-dir resolves relative path against system source directory"
    (let ((system (make-test-system :output-dir "build/")))
      (let ((resolved (tycl/asdf::resolve-tycl-output-dir system)))
        (ok resolved)
        (ok (uiop:absolute-pathname-p resolved))
        (ok (uiop:directory-pathname-p resolved))
        ;; Should end with build/
        (let ((dir-components (pathname-directory resolved)))
          (ok (equal "build" (car (last dir-components)))))))))

(deftest test-resolve-tycl-output-dir-absolute
  (testing "resolve-tycl-output-dir uses absolute path as-is"
    (let ((system (make-test-system :output-dir "/tmp/tycl-build/")))
      (let ((resolved (tycl/asdf::resolve-tycl-output-dir system)))
        (ok resolved)
        (ok (uiop:absolute-pathname-p resolved))
        (ok (uiop:directory-pathname-p resolved))
        (ok (equal (pathname-directory (uiop:ensure-directory-pathname "/tmp/tycl-build/"))
                   (pathname-directory resolved)))))))

(deftest test-tycl-file-type
  (testing "tycl-file returns 'tycl' as source-file-type"
    (let* ((system (make-test-system))
           (component (make-instance 'tycl/asdf:tycl-file
                                     :name "test-file"
                                     :parent system)))
      (ok (equal "tycl" (asdf:source-file-type component system))))))

(deftest test-transpile-tycl-op-output-files
  (testing "transpile-tycl-op output-files resolves .tycl to build/*.lisp"
    (let* ((system (make-test-system :output-dir "build/"))
           (component (make-instance 'tycl/asdf:tycl-file
                                     :name "test-file"
                                     :parent system))
           (op (asdf:make-operation 'tycl/asdf:transpile-tycl-op)))
      (multiple-value-bind (files translate-p)
          (asdf:output-files op component)
        (ok files)
        (ok translate-p)
        (let ((output (first files)))
          ;; Output should have .lisp extension
          (ok (equal "lisp" (pathname-type output)))
          ;; Output should be under build/
          (let ((dir-components (pathname-directory output)))
            (ok (member "build" dir-components :test #'equal))))))))

(deftest test-copy-source-op-output-files
  (testing "copy-source-op output-files resolves .lisp to build/*.lisp"
    (let* ((system (make-test-system :output-dir "build/"))
           (component (make-instance 'asdf:cl-source-file
                                     :name "test-file"
                                     :parent system))
           (op (asdf:make-operation 'tycl/asdf:copy-source-op)))
      (multiple-value-bind (files translate-p)
          (asdf:output-files op component)
        (ok files)
        (ok translate-p)
        (let ((output (first files)))
          ;; Output should have .lisp extension
          (ok (equal "lisp" (pathname-type output)))
          ;; Output should be under build/
          (let ((dir-components (pathname-directory output)))
            (ok (member "build" dir-components :test #'equal))))))))

(deftest test-operation-done-p-transpile-no-output
  (testing "transpile-tycl-op operation-done-p returns nil when output does not exist"
    (let* ((system (make-test-system :output-dir "/tmp/tycl-test-nonexistent/"))
           (component (make-instance 'tycl/asdf:tycl-file
                                     :name "packages"
                                     :parent system))
           (op (asdf:make-operation 'tycl/asdf:transpile-tycl-op)))
      (ok (not (asdf:operation-done-p op component))))))

(deftest test-operation-done-p-copy-no-output
  (testing "copy-source-op operation-done-p returns nil when output does not exist"
    (let* ((system (make-test-system :output-dir "/tmp/tycl-test-nonexistent/"))
           (component (make-instance 'asdf:cl-source-file
                                     :name "packages"
                                     :parent system))
           (op (asdf:make-operation 'tycl/asdf:copy-source-op)))
      (ok (not (asdf:operation-done-p op component))))))
