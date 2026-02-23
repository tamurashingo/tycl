;;;; Test for tycl-hooks.lisp loading

(defpackage #:tycl/test/tycl-hooks
  (:use #:cl #:rove))

(in-package #:tycl/test/tycl-hooks)

(defun setup-hook-test ()
  "Create test files: .tycl file and tycl-hooks.lisp"
  (ensure-directories-exist "test/temp-hooks/")
  
  ;; Create a custom macro definition in tycl-hooks.lisp
  (with-open-file (out "test/temp-hooks/tycl-hooks.lisp"
                       :direction :output
                       :if-exists :supersede)
    (write-string "(in-package #:tycl)

(register-type-extractor 'test-macro
  :type-extractor
    (lambda (form)
      (list `(:kind :value
              :symbol \"TEST-VAR\"
              :type :integer))))

(format t \"~&; Test hooks loaded successfully~%\")
" out))
  
  ;; Create a .tycl file that uses the custom macro
  (with-open-file (out "test/temp-hooks/example.tycl"
                       :direction :output
                       :if-exists :supersede)
    (write-string "(defpackage #:test-hooks-example
  (:use #:cl))

(in-package #:test-hooks-example)

(defun [test-fn :integer] ()
  42)
" out)))

(defun cleanup-hook-test ()
  "Clean up test files"
  (when (probe-file "test/temp-hooks/")
    (uiop:delete-directory-tree (truename "test/temp-hooks/") :validate t :if-does-not-exist :ignore)))

(deftest test-hooks-loading
  (testing "tycl-hooks.lisp automatic loading"
    (setup-hook-test)
    (unwind-protect
         (progn
           ;; This should load tycl-hooks.lisp from test/temp-hooks/
           (tycl:load-tycl "test/temp-hooks/example.tycl" 
                           :if-exists :overwrite 
                           :verbose nil)
           
           ;; Check that the function is defined
           (let ((test-fn-sym (find-symbol "TEST-FN" "TEST-HOOKS-EXAMPLE")))
             (ok test-fn-sym "TEST-FN symbol should exist")
             (ok (fboundp test-fn-sym) "TEST-FN should be a function")
             (ok (= (funcall test-fn-sym) 42) "TEST-FN should return 42")))
      (cleanup-hook-test))))

(deftest test-load-tycl-hooks-api
  (testing "load-tycl-hooks API"
    (setup-hook-test)
    (unwind-protect
         (progn
           ;; Clear any existing hooks
           (remhash 'test-macro tycl::*type-extractor-hooks*)
           
           ;; Load hooks manually
           (ok (tycl:load-tycl-hooks "test/temp-hooks/"))
           
           ;; Check that the hook was registered (use fully qualified symbol)
           (ok (gethash (find-symbol "TEST-MACRO" "TYCL") tycl::*type-extractor-hooks*)))
      (cleanup-hook-test))))
