;;;; TyCL Type Variables and Polymorphism Tests

(defpackage #:tycl/test/type-vars
  (:use #:cl #:rove))

(in-package #:tycl/test/type-vars)

;;; Helper

(defun transpile-with-types (tycl-string)
  "Transpile TyCL string with type extraction enabled."
  (tycl:clear-type-database)
  (tycl:transpile-string tycl-string :extract-types t))

;;; ============================================================
;;; Reader Tests
;;; ============================================================

(deftest test-read-simple-type-params
  (testing "Reading [identity <T> T] produces correct type-annotation"
    (let* ((*readtable* tycl/reader:*tycl-readtable*)
           (result (read-from-string "[identity <T> T]")))
      (ok (tycl/annotation:type-annotation-p result)
          "Result should be a type-annotation")
      (ok (eq 'identity (tycl/annotation:annotation-symbol result))
          "Symbol should be IDENTITY")
      (ok (eq 'T (tycl/annotation:annotation-type result))
          "Type should be T")
      (let ((tp (tycl/annotation:annotation-type-params result)))
        (ok tp "Should have type-params")
        (ok (tycl/annotation:type-params-p tp)
            "type-params should be a type-params struct")
        (ok (equal '(T) (tycl/annotation:type-params-entries tp))
            "type-params entries should be (T)")))))

(deftest test-read-multiple-type-params
  (testing "Reading [pair <A B> (:cons A B)] produces correct type-annotation"
    (let* ((*readtable* tycl/reader:*tycl-readtable*)
           (result (read-from-string "[pair <A B> (:cons A B)]")))
      (ok (tycl/annotation:type-annotation-p result)
          "Result should be a type-annotation")
      (ok (eq 'pair (tycl/annotation:annotation-symbol result))
          "Symbol should be PAIR")
      (ok (equal '(:cons A B) (tycl/annotation:annotation-type result))
          "Type should be (:cons A B)")
      (let ((tp (tycl/annotation:annotation-type-params result)))
        (ok tp "Should have type-params")
        (ok (equal '(A B) (tycl/annotation:type-params-entries tp))
            "type-params entries should be (A B)")))))

(deftest test-read-no-type-params
  (testing "Reading [add :integer] has no type-params (backward compat)"
    (let* ((*readtable* tycl/reader:*tycl-readtable*)
           (result (read-from-string "[add :integer]")))
      (ok (tycl/annotation:type-annotation-p result)
          "Result should be a type-annotation")
      (ok (eq 'add (tycl/annotation:annotation-symbol result))
          "Symbol should be ADD")
      (ok (eq :integer (tycl/annotation:annotation-type result))
          "Type should be :integer")
      (ok (null (tycl/annotation:annotation-type-params result))
          "type-params should be nil"))))

(deftest test-angle-brackets-outside-brackets
  (testing "< outside of brackets is still a normal symbol"
    (let* ((*readtable* tycl/reader:*tycl-readtable*)
           (result (read-from-string "(< a b)")))
      (ok (listp result)
          "Result should be a list")
      (ok (eq '< (first result))
          "First element should be < symbol")
      (ok (eq 'a (second result))
          "Second element should be A")
      (ok (eq 'b (third result))
          "Third element should be B"))))

;;; ============================================================
;;; Transpilation Tests
;;; ============================================================

(deftest test-transpile-polymorphic-defun
  (testing "Polymorphic defun transpiles correctly"
    (let ((output (tycl:transpile-string
                   "(defun [identity <T> T] ([x T]) x)")))
      (ok (stringp output))
      (ok (search "defun identity (x)" output)
          "Type annotations including type params should be stripped")
      (ok (search "x)" output)
          "Body should be preserved"))))

(deftest test-transpile-multi-param-polymorphic
  (testing "Multi-param polymorphic defun transpiles correctly"
    (let ((output (tycl:transpile-string
                   "(defun [pair <A B> (:cons A B)] ([first A] [second B]) (cons first second))")))
      (ok (stringp output))
      (ok (search "defun pair (first second)" output)
          "Function with multiple type params should transpile correctly")
      (ok (search "(cons first second)" output)
          "Body should be preserved"))))

(deftest test-transpile-mixed-forms
  (testing "Polymorphic and non-polymorphic forms coexist"
    (let ((output (tycl:transpile-string
                   "(defun [add :integer] ([x :integer] [y :integer]) (+ x y))
                    (defun [identity <T> T] ([x T]) x)")))
      (ok (stringp output))
      (ok (search "defun add (x y)" output)
          "Non-polymorphic function transpiles normally")
      (ok (search "defun identity (x)" output)
          "Polymorphic function transpiles normally"))))

;;; ============================================================
;;; Type Extraction Tests
;;; ============================================================

(deftest test-extract-polymorphic-defun-type
  (testing "Polymorphic defun extracts function-type-info with type-params"
    (tycl:clear-type-database)
    (let ((tycl:*current-package* "TEST-PKG"))
      (let* ((*readtable* tycl/reader:*tycl-readtable*)
             (form (read-from-string "(defun [identity <T> T] ([x T]) x)")))
        (tycl:extract-type-from-form form)
        (let ((info (tycl:lookup-type-info "TEST-PKG" "IDENTITY")))
          (ok info "Function type info should be registered")
          (ok (eq :function (tycl:type-info-kind info))
              "Kind should be :function")
          (ok (equal '("T") (tycl:function-type-params info))
              "type-params should be (\"T\")")
          (ok (eq 'T (tycl:function-return-type info))
              "Return type should be T"))))))

(deftest test-extract-multi-param-type
  (testing "Multi-param polymorphic defun extracts type-params correctly"
    (tycl:clear-type-database)
    (let ((tycl:*current-package* "TEST-PKG"))
      (let* ((*readtable* tycl/reader:*tycl-readtable*)
             (form (read-from-string "(defun [pair <A B> (:cons A B)] ([first A] [second B]) (cons first second))")))
        (tycl:extract-type-from-form form)
        (let ((info (tycl:lookup-type-info "TEST-PKG" "PAIR")))
          (ok info "Function type info should be registered")
          (ok (equal '("A" "B") (tycl:function-type-params info))
              "type-params should be (\"A\" \"B\")")
          (ok (equal '(:cons A B) (tycl:function-return-type info))
              "Return type should be (:cons A B)"))))))

(deftest test-extract-non-polymorphic-unchanged
  (testing "Non-polymorphic defun has nil type-params"
    (tycl:clear-type-database)
    (let ((tycl:*current-package* "TEST-PKG"))
      (let* ((*readtable* tycl/reader:*tycl-readtable*)
             (form (read-from-string "(defun [add :integer] ([x :integer] [y :integer]) (+ x y))")))
        (tycl:extract-type-from-form form)
        (let ((info (tycl:lookup-type-info "TEST-PKG" "ADD")))
          (ok info "Function type info should be registered")
          (ok (null (tycl:function-type-params info))
              "type-params should be nil for non-polymorphic functions"))))))

;;; ============================================================
;;; Serialization Round-trip Tests
;;; ============================================================

(deftest test-polymorphic-serialization-round-trip
  (testing "Polymorphic function-type-info survives serialize/deserialize round-trip"
    (tycl:clear-type-database)
    (let ((tycl:*current-package* "TEST-PKG"))
      (let* ((*readtable* tycl/reader:*tycl-readtable*)
             (form (read-from-string "(defun [identity <T> T] ([x T]) x)")))
        (tycl:extract-type-from-form form)
        (let* ((info (tycl:lookup-type-info "TEST-PKG" "IDENTITY"))
               (serialized (tycl::serialize-type-info info)))
          (ok (eq :function (first serialized))
              "Serialized form should start with :function")
          (ok (equal '("T") (getf (rest serialized) :type-params))
              "Serialized should contain :type-params (\"T\")")
          ;; Deserialize
          (tycl:clear-type-database)
          (tycl::deserialize-type-info "TEST-PKG" serialized)
          (let ((restored (tycl:lookup-type-info "TEST-PKG" "IDENTITY")))
            (ok restored "Deserialized type info should exist")
            (ok (eq :function (tycl:type-info-kind restored))
                "Restored kind should be :function")
            (ok (equal '("T") (tycl:function-type-params restored))
                "Restored type-params should be (\"T\")")))))))

(deftest test-non-polymorphic-backward-compat
  (testing "Non-polymorphic function deserialization is backward compatible"
    (tycl:clear-type-database)
    ;; Simulate old serialized format without :type-params
    (let ((old-format '(:function :symbol "ADD" :params ((:name "X" :type :integer) (:name "Y" :type :integer)) :return :integer)))
      (tycl::deserialize-type-info "TEST-PKG" old-format)
      (let ((restored (tycl:lookup-type-info "TEST-PKG" "ADD")))
        (ok restored "Deserialized type info should exist")
        (ok (null (tycl:function-type-params restored))
            "type-params should be nil for old format without :type-params")))))

;;; ============================================================
;;; Full Pipeline Tests
;;; ============================================================

(deftest test-full-pipeline-polymorphic
  (testing "Full transpile pipeline with polymorphic function"
    (let ((output (transpile-with-types
                   "(defun [identity <T> T] ([x T]) x)")))
      (ok (stringp output))
      (ok (search "defun identity (x)" output)
          "Function should be transpiled normally")
      ;; Verify type extraction
      (let ((info (tycl:lookup-type-info "COMMON-LISP-USER" "IDENTITY")))
        (ok info "Type info should be extracted")
        (ok (equal '("T") (tycl:function-type-params info))
            "type-params should be (\"T\")")))))

(deftest test-full-pipeline-with-deftype
  (testing "Full pipeline with deftype-tycl and polymorphic function"
    (let ((output (transpile-with-types
                   "(deftype-tycl userid :integer)
                    (defun [identity <T> T] ([x T]) x)
                    (defun [get-id userid] ([id userid]) id)")))
      (ok (stringp output))
      (ok (null (search "deftype-tycl" output))
          "deftype-tycl should be stripped")
      (ok (search "defun identity (x)" output)
          "Polymorphic function should be transpiled")
      (ok (search "defun get-id (id)" output)
          "Non-polymorphic function should be transpiled"))))
