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

;;; Class subtype compatibility

(deftest test-class-subtype-direct
  (testing "Direct subclass is compatible with parent type"
    (let ((errors (check-and-get-errors
                   "(defclass foo () ((x :type :integer)))
                    (defclass bar (foo) ((y :type :string)))
                    (defun [process :t] ([obj foo]) obj)
                    (defun [test-it :t] ([b bar]) (process b))")))
      (ok (null errors) "bar should be accepted where foo is expected"))))

(deftest test-class-subtype-multi-level
  (testing "Multi-level inheritance: grandchild is compatible with grandparent"
    (let ((errors (check-and-get-errors
                   "(defclass a () ((x :type :integer)))
                    (defclass b (a) ((y :type :string)))
                    (defclass c (b) ((z :type :float)))
                    (defun [process :t] ([obj a]) obj)
                    (defun [test-it :t] ([c-obj c]) (process c-obj))")))
      (ok (null errors) "c should be accepted where a is expected"))))

(deftest test-class-subtype-unrelated
  (testing "Unrelated class is not compatible"
    (multiple-value-bind (errors result)
        (check-and-get-errors
         "(defclass foo () ((x :type :integer)))
          (defclass baz () ((z :type :string)))
          (defun [process :t] ([obj foo]) obj)
          (defun [test-it :t] ([b baz]) (process b))")
      (ng result "baz is not a subtype of foo")
      (ok (not (null errors))))))

;;; &optional parameter support

(deftest test-optional-all-args-provided
  (testing "Calling with all optional arguments provided succeeds"
    (let ((errors (check-and-get-errors
                   "(defun [f :string] ([x :integer] &optional [y :string]) y)
                    (f 1 \"hello\")")))
      (ok (null errors)))))

(deftest test-optional-only-required
  (testing "Calling with only required arguments succeeds"
    (let ((errors (check-and-get-errors
                   "(defun [f :t] ([x :integer] &optional [y :string]) x)
                    (f 1)")))
      (ok (null errors)))))

(deftest test-optional-too-few-args
  (testing "Calling with fewer than required arguments produces arity error"
    (multiple-value-bind (errors result)
        (check-and-get-errors
         "(defun [f :t] ([x :integer] &optional [y :string]) x)
          (f)")
      (ng result)
      (ok (not (null errors)))
      (ok (some (lambda (err)
                  (search "expected at least 1 arguments, got 0"
                          (tycl/type-checker:error-message err)))
                errors)))))

(deftest test-optional-too-many-args
  (testing "Calling with more than total arguments produces arity error"
    (multiple-value-bind (errors result)
        (check-and-get-errors
         "(defun [f :t] ([x :integer] &optional [y :string]) x)
          (f 1 \"a\" 3)")
      (ng result)
      (ok (not (null errors)))
      (ok (some (lambda (err)
                  (search "expected 1 to 2 arguments, got 3"
                          (tycl/type-checker:error-message err)))
                errors)))))

(deftest test-optional-type-mismatch
  (testing "Optional argument with wrong type produces type error"
    (multiple-value-bind (errors result)
        (check-and-get-errors
         "(defun [f :string] ([x :integer] &optional [y :string]) y)
          (f 1 42)")
      (ng result)
      (ok (not (null errors)))
      (ok (search "type mismatch" (tycl/type-checker:error-message (first errors)))))))

(deftest test-all-optional-no-args
  (testing "Function with all optional params can be called with no args"
    (let ((errors (check-and-get-errors
                   "(defun [f :t] (&optional [x :integer] [y :string]) x)
                    (f)")))
      (ok (null errors)))))

(deftest test-optional-with-default-value
  (testing "Optional parameter with default value syntax works"
    (let ((errors (check-and-get-errors
                   "(defun [f :string] ([x :integer] &optional ([y :string] \"default\")) y)
                    (f 1)")))
      (ok (null errors)))))

;;; &key parameter support

(deftest test-key-with-args
  (testing "Calling with &key arguments succeeds"
    (let ((errors (check-and-get-errors
                   "(defun [f :t] ([x :integer] &key [test :function]) x)
                    (f 1 :test #'equal)")))
      (ok (null errors)))))

(deftest test-key-omitted
  (testing "Calling without &key arguments succeeds"
    (let ((errors (check-and-get-errors
                   "(defun [f :t] ([x :integer] &key [test :function]) x)
                    (f 1)")))
      (ok (null errors)))))

(deftest test-key-unknown-keyword
  (testing "Unknown keyword argument produces error"
    (multiple-value-bind (errors result)
        (check-and-get-errors
         "(defun [f :t] ([x :integer] &key [test :function]) x)
          (f 1 :unknown #'equal)")
      (ng result)
      (ok (not (null errors)))
      (ok (some (lambda (err)
                  (search "unknown keyword argument" (tycl/type-checker:error-message err)))
                errors)))))

(deftest test-key-type-mismatch
  (testing "Keyword argument type mismatch produces error"
    (multiple-value-bind (errors result)
        (check-and-get-errors
         "(defun [f :t] ([x :integer] &key [verbose :boolean]) x)
          (f 1 :verbose 42)")
      (ng result)
      (ok (not (null errors)))
      (ok (some (lambda (err)
                  (search "type mismatch" (tycl/type-checker:error-message err)))
                errors)))))

(deftest test-key-order-swap
  (testing "Keyword arguments in different order succeeds"
    (let ((errors (check-and-get-errors
                   "(defun [f :t] ([x :integer] &key [a :string] [b :integer]) x)
                    (f 1 :b 42 :a \"hello\")")))
      (ok (null errors)))))

(deftest test-optional-and-key
  (testing "&optional + &key mixed usage succeeds"
    (let ((errors (check-and-get-errors
                   "(defun [f :t] ([x :integer] &optional [y :string] &key [verbose :boolean]) x)
                    (f 1 \"hello\" :verbose t)")))
      (ok (null errors)))))

(deftest test-key-odd-number
  (testing "Odd number of keyword arguments produces error"
    (multiple-value-bind (errors result)
        (check-and-get-errors
         "(defun [f :t] ([x :integer] &key [test :function]) x)
          (f 1 :test)")
      (ng result)
      (ok (not (null errors)))
      (ok (some (lambda (err)
                  (search "odd number" (tycl/type-checker:error-message err)))
                errors)))))

(deftest test-key-only-no-args
  (testing "&key only function called with no args succeeds"
    (let ((errors (check-and-get-errors
                   "(defun [f :t] (&key [test :function] [size :integer]) nil)
                    (f)")))
      (ok (null errors)))))

(deftest test-key-with-default-value
  (testing "&key with default value succeeds"
    (let ((errors (check-and-get-errors
                   "(defun [f :t] ([x :integer] &key ([test :function] #'eql)) x)
                    (f 1)")))
      (ok (null errors)))))

;;; &rest parameter support

(deftest test-rest-with-extra-args
  (testing "Calling with extra &rest arguments succeeds"
    (let ((errors (check-and-get-errors
                   "(defun [f :t] ([x :integer] &rest [args :t]) x)
                    (f 1 2 3 4)")))
      (ok (null errors)))))

(deftest test-rest-no-extra-args
  (testing "Calling with only required args succeeds (&rest gets empty)"
    (let ((errors (check-and-get-errors
                   "(defun [f :t] ([x :integer] &rest [args :t]) x)
                    (f 1)")))
      (ok (null errors)))))

(deftest test-rest-too-few-args
  (testing "Calling with fewer than required args produces error"
    (multiple-value-bind (errors result)
        (check-and-get-errors
         "(defun [f :t] ([x :integer] [y :string] &rest [args :t]) x)
          (f 1)")
      (ng result)
      (ok (not (null errors)))
      (ok (some (lambda (err)
                  (search "expected at least 2 arguments, got 1"
                          (tycl/type-checker:error-message err)))
                errors)))))

(deftest test-rest-type-check
  (testing "&rest argument type mismatch produces error"
    (multiple-value-bind (errors result)
        (check-and-get-errors
         "(defun [f :t] ([x :integer] &rest [args :string]) x)
          (f 1 \"a\" 42)")
      (ng result)
      (ok (not (null errors)))
      (ok (some (lambda (err)
                  (search "type mismatch" (tycl/type-checker:error-message err)))
                errors)))))

(deftest test-rest-type-check-all-match
  (testing "&rest arguments with correct types succeed"
    (let ((errors (check-and-get-errors
                   "(defun [f :t] ([x :integer] &rest [args :string]) x)
                    (f 1 \"a\" \"b\" \"c\")")))
      (ok (null errors)))))

(deftest test-rest-only
  (testing "&rest only function accepts any number of args"
    (let ((errors (check-and-get-errors
                   "(defun [f :t] (&rest [args :integer]) nil)
                    (f)
                    (f 1)
                    (f 1 2 3)")))
      (ok (null errors)))))

(deftest test-optional-and-rest
  (testing "&optional + &rest mixed usage succeeds"
    (let ((errors (check-and-get-errors
                   "(defun [f :t] ([x :integer] &optional [y :string] &rest [args :t]) x)
                    (f 1)
                    (f 1 \"hello\")
                    (f 1 \"hello\" 2 3 4)")))
      (ok (null errors)))))

;;; Generic type vs atom incompatibility

(deftest test-generic-type-rejects-atom
  (testing "Passing :string to (:list (:string)) produces type error"
    (multiple-value-bind (errors result)
        (check-and-get-errors
         "(defun [process :t] ([items (:list (:string))]) items)
          (defun [test-it :t] ([s :string]) (process s))")
      (ng result)
      (ok (not (null errors)))
      (ok (some (lambda (err)
                  (search "type mismatch" (tycl/type-checker:error-message err)))
                errors)))))

(deftest test-generic-type-accepts-same
  (testing "Passing (:list (:string)) to (:list (:string)) succeeds"
    (let ((errors (check-and-get-errors
                   "(defun [process :t] ([items (:list (:string))]) items)
                    (defun [wrap :t] ([items (:list (:string))]) (process items))")))
      (ok (null errors)))))

(deftest test-union-type-still-works
  (testing "Union type (:string :null) still accepts :string"
    (let ((errors (check-and-get-errors
                   "(defun [f :t] ([x (:string :null)]) x)
                    (f \"hello\")")))
      (ok (null errors)))))

(deftest test-rest-param-passes-to-list-generic
  (testing "&rest param is compatible with (:list (:string)) param"
    (let ((errors (check-and-get-errors
                   "(defun [consume :t] ([items (:list (:string))]) items)
                    (defun [f :t] (&rest [args :string]) (consume args))")))
      (ok (null errors)))))

;;; Generic type: hash-table

(deftest test-hash-table-generic-accepts-same
  (testing "Passing (:hash-table (:string) (:string)) to same type succeeds"
    (let ((errors (check-and-get-errors
                   "(defun [get-val :t] ([tbl (:hash-table (:string) (:string))]) tbl)
                    (defun [wrap :t] ([tbl (:hash-table (:string) (:string))]) (get-val tbl))")))
      (ok (null errors)))))

(deftest test-hash-table-generic-rejects-atom
  (testing "Passing :string to (:hash-table (:string) (:string)) produces error"
    (multiple-value-bind (errors result)
        (check-and-get-errors
         "(defun [get-val :t] ([tbl (:hash-table (:string) (:string))]) tbl)
          (defun [test-it :t] ([s :string]) (get-val s))")
      (ng result)
      (ok (not (null errors)))
      (ok (some (lambda (err)
                  (search "type mismatch" (tycl/type-checker:error-message err)))
                errors)))))

(deftest test-hash-table-generic-param-mismatch
  (testing "(:hash-table (:string) (:integer)) is not compatible with (:hash-table (:string) (:string))"
    (multiple-value-bind (errors result)
        (check-and-get-errors
         "(defun [get-val :t] ([tbl (:hash-table (:string) (:string))]) tbl)
          (defun [test-it :t] ([tbl (:hash-table (:string) (:integer))]) (get-val tbl))")
      (ng result)
      (ok (not (null errors))))))

;;; Union types with generic types

(deftest test-union-list-string-or-null-accepts-list
  (testing "(:list (:string)) is compatible with ((:list (:string)) :null)"
    (let ((errors (check-and-get-errors
                   "(defun [f :t] ([x ((:list (:string)) :null)]) x)
                    (defun [test-it :t] ([items (:list (:string))]) (f items))")))
      (ok (null errors)))))

(deftest test-union-list-string-or-null-accepts-null
  (testing ":null is compatible with ((:list (:string)) :null)"
    (let ((errors (check-and-get-errors
                   "(defun [f :t] ([x ((:list (:string)) :null)]) x)
                    (f nil)")))
      (ok (null errors)))))

(deftest test-union-list-string-or-null-rejects-integer
  (testing ":integer is not compatible with ((:list (:string)) :null)"
    (multiple-value-bind (errors result)
        (check-and-get-errors
         "(defun [f :t] ([x ((:list (:string)) :null)]) x)
          (defun [test-it :t] ([n :integer]) (f n))")
      (ng result)
      (ok (not (null errors)))
      (ok (some (lambda (err)
                  (search "type mismatch" (tycl/type-checker:error-message err)))
                errors)))))

(deftest test-union-hashtable-or-null-accepts-hashtable
  (testing "(:hash-table (:integer) (:string)) is compatible with ((:hash-table (:integer) (:string)) :null)"
    (let ((errors (check-and-get-errors
                   "(defun [f :t] ([x ((:hash-table (:integer) (:string)) :null)]) x)
                    (defun [test-it :t] ([tbl (:hash-table (:integer) (:string))]) (f tbl))")))
      (ok (null errors)))))

(deftest test-union-hashtable-or-null-rejects-integer
  (testing ":integer is not compatible with ((:hash-table (:integer) (:string)) :null)"
    (multiple-value-bind (errors result)
        (check-and-get-errors
         "(defun [f :t] ([x ((:hash-table (:integer) (:string)) :null)]) x)
          (defun [test-it :t] ([n :integer]) (f n))")
      (ng result)
      (ok (not (null errors))))))

(deftest test-union-custom-classes-or-null
  (testing "my-class-a is compatible with (my-class-a my-class-b :null)"
    (let ((errors (check-and-get-errors
                   "(defclass my-class-a () ())
                    (defclass my-class-b () ())
                    (defun [f :t] ([x (my-class-a my-class-b :null)]) x)
                    (defun [test-it :t] ([a my-class-a]) (f a))")))
      (ok (null errors)))))

(deftest test-union-custom-classes-or-null-rejects-integer
  (testing ":integer is not compatible with (my-class-a my-class-b :null)"
    (multiple-value-bind (errors result)
        (check-and-get-errors
         "(defclass my-class-a () ())
          (defclass my-class-b () ())
          (defun [f :t] ([x (my-class-a my-class-b :null)]) x)
          (defun [test-it :t] ([n :integer]) (f n))")
      (ng result)
      (ok (not (null errors))))))

(deftest test-union-generic-custom-class-or-null-accepts
  (testing "(my-class-c (:string)) is compatible with ((my-class-c (:string)) :null)"
    (let ((errors (check-and-get-errors
                   "(defun [f :t] ([x ((my-class-c (:string)) :null)]) x)
                    (defun [test-it :t] ([c (my-class-c (:string))]) (f c))")))
      (ok (null errors)))))

(deftest test-union-generic-custom-class-or-null-rejects
  (testing ":integer is not compatible with ((my-class-c (:string)) :null)"
    (multiple-value-bind (errors result)
        (check-and-get-errors
         "(defun [f :t] ([x ((my-class-c (:string)) :null)]) x)
          (defun [test-it :t] ([n :integer]) (f n))")
      (ng result)
      (ok (not (null errors))))))

(deftest test-union-generic-multi-param-or-null-accepts
  (testing "(my-class-d (my-class-e my-class-f)) is compatible with ((my-class-d (my-class-e my-class-f)) :null)"
    (let ((errors (check-and-get-errors
                   "(defun [f :t] ([x ((my-class-d (my-class-e my-class-f)) :null)]) x)
                    (defun [test-it :t] ([d (my-class-d (my-class-e my-class-f))]) (f d))")))
      (ok (null errors)))))

(deftest test-union-generic-multi-param-or-null-rejects
  (testing ":integer is not compatible with ((my-class-d (my-class-e my-class-f)) :null)"
    (multiple-value-bind (errors result)
        (check-and-get-errors
         "(defun [f :t] ([x ((my-class-d (my-class-e my-class-f)) :null)]) x)
          (defun [test-it :t] ([n :integer]) (f n))")
      (ng result)
      (ok (not (null errors))))))

;;; Class subtype compatibility

(deftest test-class-subtype-reverse
  (testing "Parent class is not compatible with child type"
    (multiple-value-bind (errors result)
        (check-and-get-errors
         "(defclass foo () ((x :type :integer)))
          (defclass bar (foo) ((y :type :string)))
          (defun [process :t] ([obj bar]) obj)
          (defun [test-it :t] ([f foo]) (process f))")
      (ng result "foo is not a subtype of bar")
      (ok (not (null errors))))))
