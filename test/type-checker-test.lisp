;;;; TyCL Type Checker Tests

(defpackage #:tycl/test/type-checker
  (:use #:cl #:rove))

(in-package #:tycl/test/type-checker)

;;; Helper to run type checking on a string and return (values result errors)
(defun check-and-get-errors (tycl-string)
  "Run type checking on a TyCL string and return the list of errors."
  (tycl:clear-type-database)
  (let ((result (tycl/type-checker:check-string tycl-string)))
    (values (reverse tycl/type-checker:*type-check-errors*) result)))

;;; Valid defun

(deftest test-valid-defun
  (testing "Valid defun with correct type annotations passes"
    (multiple-value-bind (errors result)
        (check-and-get-errors
         "(defun [add :integer] ([x :integer] [y :integer]) (+ x y))")
      (ok result "check-string should return t on success")
      (ok (null errors)))))

;;; Invalid type keyword

(deftest test-invalid-type-keyword
  (testing "Invalid type keyword produces error"
    (multiple-value-bind (errors result)
        (check-and-get-errors "(defun [add :invalid-type] ([x :integer]) x)")
      (ng result "check-string should return nil on error")
      (ok (not (null errors)))
      (ok (search "Invalid" (tycl/type-checker:error-message (first errors)))))))

;;; Return type mismatch

(deftest test-return-type-mismatch
  (testing "Return type mismatch when declaring :integer but returning string"
    (multiple-value-bind (errors result)
        (check-and-get-errors "(defun [f :integer] () \"hello\")")
      (ng result "check-string should return nil on error")
      (ok (not (null errors)))
      (ok (search "mismatch" (tycl/type-checker:error-message (first errors)))))))

;;; Let binding type mismatch

(deftest test-let-binding-type-mismatch
  (testing "Let binding type mismatch when declaring :integer but binding string"
    (multiple-value-bind (errors result)
        (check-and-get-errors "(let (([x :integer] \"string\")) x)")
      (ng result "check-string should return nil on error")
      (ok (not (null errors)))
      (ok (search "mismatch" (tycl/type-checker:error-message (first errors)))))))

;;; Let binding consistent types

(deftest test-let-binding-consistent
  (testing "Let binding with consistent types passes"
    (let ((errors (check-and-get-errors
                   "(let (([x :integer] 42)) x)")))
      (ok (null errors)))))

;;; Function call argument count mismatch

(deftest test-function-call-arg-count
  (testing "Function call with wrong argument count"
    (multiple-value-bind (errors result)
        (check-and-get-errors
         "(defun [add :integer] ([x :integer] [y :integer]) (+ x y))
          (add 1 2 3)")
      (ng result "check-string should return nil on error")
      (ok (not (null errors)))
      (ok (search "expected 2 arguments, got 3"
                   (tycl/type-checker:error-message (first errors)))))))

;;; Function call argument type mismatch

(deftest test-function-call-arg-type
  (testing "Function call with wrong argument type"
    (multiple-value-bind (errors result)
        (check-and-get-errors
         "(defun [greet :string] ([name :string]) name)
          (greet 42)")
      (ng result "check-string should return nil on error")
      (ok (not (null errors)))
      (ok (search "type mismatch" (tycl/type-checker:error-message (first errors)))))))

;;; flet type checking

(deftest test-flet-type-check
  (testing "flet local function definitions are type checked"
    (multiple-value-bind (errors result)
        (check-and-get-errors
         "(flet (([helper :integer] () \"wrong-type\"))
            (helper))")
      (ng result "check-string should return nil on error")
      (ok (not (null errors)))
      (ok (search "mismatch" (tycl/type-checker:error-message (first errors)))))))

;;; Default type checking OFF

(deftest test-default-check-off
  (testing "With *enable-type-checking* nil, transpile succeeds even with type errors"
    (let ((tycl/type-checker:*enable-type-checking* nil))
      (let ((result (tycl:transpile-string
                     "(defun [f :integer] () \"hello\")")))
        (ok (stringp result))
        (ok (search "defun f ()" result))))))

;;; Check ON with :warn mode

(deftest test-check-on-warn
  (testing "With *enable-type-checking* t, transpile succeeds with warnings"
    (tycl:clear-type-database)
    (let ((tycl/type-checker:*enable-type-checking* t)
          (warnings nil))
      (handler-bind ((warning (lambda (w)
                                (push (format nil "~A" w) warnings)
                                (muffle-warning w))))
        (let ((result (tycl:transpile-string
                       "(defun [f :integer] () \"hello\")"
                       :extract-types t)))
          (ok (stringp result))
          (ok (not (null warnings))))))))

;;; Check ON with :error mode

(deftest test-check-on-error
  (testing "With *enable-type-checking* :error, transpile signals error on type mismatch"
    (tycl:clear-type-database)
    (let ((tycl/type-checker:*enable-type-checking* :error)
          (error-signaled nil))
      (handler-case
          (handler-bind ((warning #'muffle-warning))
            (tycl:transpile-string
             "(defun [f :integer] () \"hello\")"
             :extract-types t))
        (error (e)
          (setf error-signaled t)
          (ok (search "failed" (format nil "~A" e)))))
      (ok error-signaled "transpile-string should signal an error"))))

;;; Untyped variables accepted as :t

(deftest test-untyped-variable
  (testing "Untyped variables are accepted as :t"
    (let ((errors (check-and-get-errors
                   "(let ((x 42)) x)")))
      (ok (null errors)))))

;;; Multiple error collection

(deftest test-multiple-errors
  (testing "Multiple errors are collected without stopping at the first one"
    (multiple-value-bind (errors result)
        (check-and-get-errors
         "(defun [f :invalid-type1] () nil)
          (defun [g :invalid-type2] () nil)")
      (ng result "check-string should return nil on error")
      (ok (>= (length errors) 2)))))

;;; Valid let* with sequential bindings

(deftest test-valid-let-star
  (testing "let* with sequential bindings passes"
    (let ((errors (check-and-get-errors
                   "(let* (([x :integer] 10) ([y :integer] 20)) (+ x y))")))
      (ok (null errors)))))

;;; labels recursive function

(deftest test-labels-type-check
  (testing "labels local function definitions are type checked"
    (let ((errors (check-and-get-errors
                   "(labels (([helper :integer] ([n :integer]) n))
                      (helper 5))")))
      (ok (null errors)))))

;;; lambda type checking

(deftest test-lambda-type-check
  (testing "lambda parameter types are checked"
    (let ((errors (check-and-get-errors
                   "(lambda ([x :integer]) x)")))
      (ok (null errors)))))

;;; defmethod type checking

(deftest test-defmethod-type-check
  (testing "defmethod is type checked like defun"
    (let ((errors (check-and-get-errors
                   "(defmethod [greet :string] ([name :string]) name)")))
      (ok (null errors)))))
