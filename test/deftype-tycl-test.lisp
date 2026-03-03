;;;; TyCL deftype-tycl Tests

(defpackage #:tycl/test/deftype-tycl
  (:use #:cl #:rove))

(in-package #:tycl/test/deftype-tycl)

;;; Helper

(defun transpile-with-types (tycl-string)
  "Transpile TyCL string with type extraction enabled."
  (tycl:clear-type-database)
  (tycl:transpile-string tycl-string :extract-types t))

(defun check-and-get-errors (tycl-string)
  "Run type checking on a TyCL string and return the list of errors."
  (tycl:clear-type-database)
  (let ((result (tycl/type-checker:check-string tycl-string)))
    (values (reverse tycl/type-checker:*type-check-errors*) result)))

;;; Basic transpilation: deftype-tycl should be stripped from output

(deftest test-deftype-tycl-stripped
  (testing "deftype-tycl forms are stripped from transpiled output"
    (let ((output (transpile-with-types
                   "(deftype-tycl userid :integer)
                    (defun [get-id :integer] () 42)")))
      (ok (stringp output))
      (ok (null (search "deftype-tycl" output))
          "deftype-tycl should not appear in output")
      (ok (search "defun get-id" output)
          "defun should still appear in output"))))

;;; Type alias registration

(deftest test-type-alias-registration
  (testing "deftype-tycl registers type alias in database"
    (tycl:clear-type-database)
    (let ((tycl:*current-package* "TEST-PKG"))
      (tycl:extract-type-from-form '(deftype-tycl userid :integer))
      (ok (tycl:lookup-type-alias "TEST-PKG" "USERID")
          "Type alias should be registered")
      (ok (eq :integer (tycl:lookup-type-alias "TEST-PKG" "USERID"))
          "Alias should expand to :integer"))))

;;; Compound type alias

(deftest test-compound-type-alias
  (testing "deftype-tycl with compound type"
    (tycl:clear-type-database)
    (let ((tycl:*current-package* "TEST-PKG"))
      (tycl:extract-type-from-form '(deftype-tycl string-list (:list :string)))
      (let ((expanded (tycl:lookup-type-alias "TEST-PKG" "STRING-LIST")))
        (ok expanded "Type alias should be registered")
        (ok (equal '(:list :string) expanded)
            "Alias should expand to (:list :string)")))))

;;; Type alias resolution

(deftest test-resolve-type-alias
  (testing "resolve-type-alias expands aliases correctly"
    (tycl:clear-type-database)
    (let ((tycl:*current-package* "TEST-PKG"))
      (tycl:extract-type-from-form '(deftype-tycl userid :integer))
      ;; Resolve symbol
      (ok (eq :integer (tycl:resolve-type-alias 'userid "TEST-PKG"))
          "Symbol alias should resolve to :integer")
      ;; Keywords pass through
      (ok (eq :string (tycl:resolve-type-alias :string "TEST-PKG"))
          "Keywords should pass through unchanged")
      ;; Non-alias symbols pass through
      (ok (eq 'unknown (tycl:resolve-type-alias 'unknown "TEST-PKG"))
          "Non-alias symbols should pass through unchanged"))))

;;; Recursive alias resolution (chained aliases)

(deftest test-recursive-alias-resolution
  (testing "Chained aliases are resolved recursively"
    (tycl:clear-type-database)
    (let ((tycl:*current-package* "TEST-PKG"))
      (tycl:extract-type-from-form '(deftype-tycl userid :integer))
      (tycl:extract-type-from-form '(deftype-tycl admin-id userid))
      (ok (eq :integer (tycl:resolve-type-alias 'admin-id "TEST-PKG"))
          "admin-id -> userid -> :integer"))))

;;; Type compatibility with aliases

(deftest test-type-compatible-with-alias
  (testing "type-compatible-p resolves aliases before comparison"
    (multiple-value-bind (errors result)
        (check-and-get-errors
         "(deftype-tycl userid :integer)
          (defun [get-id :integer] ([id userid]) id)")
      (ok result "Alias type should be compatible with its expansion")
      (ok (null errors) "No errors when alias matches expected type"))))

;;; Type checking with deftype-tycl

(deftest test-type-check-with-alias
  (testing "Type checking works with type aliases"
    (multiple-value-bind (errors result)
        (check-and-get-errors
         "(deftype-tycl userid :integer)
          (defun [get-id userid] () 42)")
      (ok result "Type checking should pass with valid alias usage")
      (ok (null errors) "No errors expected"))))

(deftest test-type-check-alias-mismatch
  (testing "Type checking detects mismatch through alias"
    (multiple-value-bind (errors result)
        (check-and-get-errors
         "(deftype-tycl userid :integer)
          (defun [get-id userid] () \"not-an-integer\")")
      (ng result "Type checking should fail with alias mismatch")
      (ok (not (null errors)) "Should have type errors"))))

;;; Serialization round-trip

(deftest test-serialization-round-trip
  (testing "Type alias survives serialize/deserialize round-trip"
    (tycl:clear-type-database)
    (let ((tycl:*current-package* "TEST-PKG"))
      (tycl:extract-type-from-form '(deftype-tycl userid :integer))
      (let* ((info (tycl:lookup-type-info "TEST-PKG" "USERID"))
             (serialized (tycl::serialize-type-info info)))
        (ok (eq :type-alias (first serialized))
            "Serialized form should start with :type-alias")
        (ok (string= "USERID" (getf (rest serialized) :symbol))
            "Serialized symbol should be USERID")
        (ok (eq :integer (getf (rest serialized) :expanded-type))
            "Serialized expanded-type should be :integer")
        ;; Deserialize
        (tycl:clear-type-database)
        (tycl::deserialize-type-info "TEST-PKG" serialized)
        (let ((restored (tycl:lookup-type-info "TEST-PKG" "USERID")))
          (ok restored "Deserialized type info should exist")
          (ok (eq :type-alias (tycl:type-info-kind restored))
              "Restored kind should be :type-alias")
          (ok (eq :integer (tycl:alias-expanded-type restored))
              "Restored expanded-type should be :integer"))))))

;;; Package scope

(deftest test-package-scoped-aliases
  (testing "Type aliases are scoped to their package"
    (tycl:clear-type-database)
    (let ((tycl:*current-package* "PKG-A"))
      (tycl:extract-type-from-form '(deftype-tycl mytype :integer)))
    (let ((tycl:*current-package* "PKG-B"))
      (tycl:extract-type-from-form '(deftype-tycl mytype :string)))
    (ok (eq :integer (tycl:lookup-type-alias "PKG-A" "MYTYPE"))
        "PKG-A's mytype should be :integer")
    (ok (eq :string (tycl:lookup-type-alias "PKG-B" "MYTYPE"))
        "PKG-B's mytype should be :string")))

;;; Full transpile pipeline with deftype-tycl

(deftest test-full-pipeline
  (testing "Full transpile pipeline with deftype-tycl and typed function"
    (let ((output (transpile-with-types
                   "(deftype-tycl userid :integer)
                    (deftype-tycl name-type :string)
                    (defun [get-user name-type] ([id userid]) (fetch-user id))")))
      (ok (stringp output))
      (ok (null (search "deftype-tycl" output))
          "No deftype-tycl in output")
      (ok (search "defun get-user (id)" output)
          "Function should be transpiled normally"))))
