;;;; Test for load-tycl function

(defpackage #:tycl/test/load-tycl
  (:use #:cl #:rove))

(in-package #:tycl/test/load-tycl)

(defun setup-test-file ()
  "Create a test .tycl file"
  (ensure-directories-exist "test/temp/")
  (with-open-file (out "test/temp/example.tycl"
                       :direction :output
                       :if-exists :supersede)
    (write-string "(defpackage #:test-example
  (:use #:cl)
  (:export #:add #:greet))

(in-package #:test-example)

(defun [add :integer] ([x :integer] [y :integer])
  \"Add two integers\"
  (+ x y))

(defun [greet :string] ([name :string])
  \"Greet a person\"
  (format nil \"Hello, ~A!\" name))
" out)))

(defun cleanup-test-files ()
  "Clean up test files"
  (when (probe-file "test/temp/")
    (uiop:delete-directory-tree (truename "test/temp/") :validate t :if-does-not-exist :ignore)))

(deftest test-basic-load
  (testing "Basic load-tycl functionality"
    (setup-test-file)
    (unwind-protect
         (progn
           (tycl:load-tycl "test/temp/example.tycl" :if-exists :overwrite :verbose nil)
           (let ((add-sym (find-symbol "ADD" "TEST-EXAMPLE"))
                 (greet-sym (find-symbol "GREET" "TEST-EXAMPLE")))
             (ok add-sym "ADD symbol should exist")
             (ok (fboundp add-sym) "ADD should be a function")
             (ok (= (funcall add-sym 3 4) 7) "ADD should return 7")
             (ok greet-sym "GREET symbol should exist")
             (ok (fboundp greet-sym) "GREET should be a function")
             (ok (string= (funcall greet-sym "Alice") "Hello, Alice!") "GREET should return greeting")))
      (cleanup-test-files))))

(deftest test-if-exists-error
  (testing ":if-exists :error (default)"
    (setup-test-file)
    (unwind-protect
         (progn
           ;; First load
           (tycl:load-tycl "test/temp/example.tycl" :if-exists :overwrite :verbose nil)
           ;; Second load should error
           (ok (signals (tycl:load-tycl "test/temp/example.tycl" :verbose nil)
                        'error)))
      (cleanup-test-files))))

(deftest test-if-exists-overwrite
  (testing ":if-exists :overwrite"
    (setup-test-file)
    (unwind-protect
         (progn
           ;; First load
           (tycl:load-tycl "test/temp/example.tycl" :if-exists :overwrite :verbose nil)
           ;; Second load with overwrite should succeed
           (ok (tycl:load-tycl "test/temp/example.tycl" :if-exists :overwrite :verbose nil)))
      (cleanup-test-files))))

(deftest test-output-dir
  (testing ":output-dir option"
    (setup-test-file)
    (unwind-protect
         (progn
           (ensure-directories-exist "test/temp/build/")
           (tycl:load-tycl "test/temp/example.tycl" 
                           :output-dir "test/temp/build/"
                           :if-exists :overwrite
                           :verbose nil)
           (ok (probe-file "test/temp/build/example.lisp")))
      (cleanup-test-files))))

(deftest test-compile-and-load
  (testing "compile-and-load-tycl"
    (setup-test-file)
    (unwind-protect
         (progn
           (tycl:compile-and-load-tycl "test/temp/example.tycl" 
                                        :if-exists :overwrite
                                        :verbose nil)
           (ok (probe-file (compile-file-pathname "test/temp/example.lisp"))))
      (cleanup-test-files))))
