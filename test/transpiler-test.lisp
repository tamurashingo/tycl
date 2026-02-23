;;;; TyCL Transpiler Tests

(defpackage #:tycl/test/transpiler
  (:use #:cl #:rove))

(in-package #:tycl/test/transpiler)

(deftest test-simple-transpilation
  (testing "Simple form transpilation"
    (let* ((input "(defun [add :integer] ([x :integer] [y :integer]) (+ x y))")
           (output (tycl:transpile-string input)))
      (ok (stringp output))
      (ok (search "defun add (x y)" output)))))

(deftest test-let-form
  (testing "Let form transpilation"
    (let* ((input "(let (([x :integer] 10) (y 20)) (+ x y))")
           (output (tycl:transpile-string input)))
      (ok (stringp output))
      (ok (search "let ((x 10) (y 20))" output)))))

(deftest test-union-types
  (testing "Union type transpilation"
    (let* ((input "(defun [process :void] ([value (:integer :string)]) nil)")
           (output (tycl:transpile-string input)))
      (ok (stringp output))
      (ok (search "defun process (value)" output)))))

(deftest test-generics
  (testing "Generic type transpilation"
    (let* ((input "(defun [get-items (:list (:integer))] () '(1 2 3))")
           (output (tycl:transpile-string input)))
      (ok (stringp output))
      (ok (search "defun get-items () '(1 2 3)" output)))))

(deftest test-nested-generics
  (testing "Nested generic type transpilation"
    (let* ((input "(defvar [*cache* (:hash-table (:string) (:list (:integer)))] nil)")
           (output (tycl:transpile-string input)))
      (ok (stringp output))
      (ok (search "defvar *cache* nil" output)))))

(deftest test-type-checking-valid
  (testing "Type checking - valid types"
    (let ((input "(defun [add :integer] ([x :integer] [y :integer]) (+ x y))"))
      (ok (tycl:check-string input)))))

(deftest test-type-checking-invalid
  (testing "Type checking - invalid types"
    (let ((input "(defun [add :invalid-type] ([x :integer] [y :integer]) (+ x y))"))
      (ok (not (tycl:check-string input))))))
