;;;; Sample test for TyCL Phase 5 features
;;;; Tests type information extraction and serialization

(in-package #:cl-user)
(defpackage #:tycl/test/sample
  (:use #:cl)
  (:import-from #:rove
                #:deftest
                #:testing
                #:ok))
(in-package #:tycl/test/sample)

(deftest basic-transpile-test
  (testing "Basic transpilation works"
    (let ((result (tycl:transpile-string "(defun [add :integer] ([x :integer] [y :integer]) (+ x y))")))
      (ok (stringp result))
      (ok (search "(defun add (x y)" result)))))

(deftest type-extraction-test
  (testing "Type information is extracted during transpilation"
    ;; Clear database first
    (tycl:clear-type-database)
    
    ;; Transpile with type extraction
    (let ((tycl::*current-package* "TEST-PACKAGE"))
      (tycl:transpile-string 
       "(defun [add :integer] ([x :integer] [y :integer]) (+ x y))"
       :extract-types t))
    
    ;; Check if type info was registered
    (let ((info (tycl:lookup-type-info "TEST-PACKAGE" "ADD")))
      (ok info "Type info should be registered")
      (when info
        (ok (typep info 'tycl:function-type-info) "Should be function type info")
        (ok (equal (tycl:function-return-type info) :integer) "Return type should be :integer")
        (ok (= 2 (length (tycl:function-params info))) "Should have 2 parameters")))))

(deftest value-type-extraction-test
  (testing "Value type information is extracted"
    (tycl:clear-type-database)
    
    (let ((tycl::*current-package* "TEST-PACKAGE"))
      (tycl:transpile-string
       "(defvar [*config* :string] \"default\")"
       :extract-types t))
    
    (let ((info (tycl:lookup-type-info "TEST-PACKAGE" "*CONFIG*")))
      (ok info "Type info should be registered")
      (when info
        (ok (typep info 'tycl:value-type-info) "Should be value type info")
        (ok (equal (tycl:value-type-spec info) :string) "Type should be :string")))))

(deftest class-type-extraction-test
  (testing "Class type information is extracted"
    (tycl:clear-type-database)
    
    (let ((tycl::*current-package* "TEST-PACKAGE"))
      (tycl:transpile-string
       "(defclass user () (([name :string]) ([age :integer])))"
       :extract-types t))
    
    (let ((info (tycl:lookup-type-info "TEST-PACKAGE" "USER")))
      (ok info "Type info should be registered")
      (when info
        (ok (typep info 'tycl:class-type-info) "Should be class type info")
        (ok (= 2 (length (tycl:class-slots info))) "Should have 2 slots")))))

(deftest package-symbols-test
  (testing "Package symbols can be queried"
    (tycl:clear-type-database)
    
    (let ((tycl::*current-package* "TEST-PKG"))
      (tycl:transpile-string
       "(defun [foo :integer] () 42) (defvar [*bar* :string] \"test\")"
       :extract-types t))
    
    (let ((symbols (tycl:get-package-symbols "TEST-PKG")))
      (ok symbols "Should have symbols")
      (ok (member "FOO" symbols :test #'string=) "Should include FOO")
      (ok (member "*BAR*" symbols :test #'string=) "Should include *BAR*"))))
