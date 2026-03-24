;;;; TyCL defgeneric Type Support Tests

(defpackage #:tycl/test/defgeneric
  (:use #:cl #:rove))

(in-package #:tycl/test/defgeneric)

;;; Helper to run type checking on a string and return (values errors result)
(defun check-and-get-errors (tycl-string)
  "Run type checking on a TyCL string and return the list of errors."
  (tycl:clear-type-database)
  (let ((result (tycl/type-checker:check-string tycl-string)))
    (values (reverse tycl/type-checker:*type-check-errors*) result)))

;;; ============================================================
;;; Type Extraction Tests
;;; ============================================================

(deftest test-defgeneric-type-extraction
  (testing "defgeneric extracts type information correctly"
    (tycl:clear-type-database)
    (let ((tycl:*current-package* "TEST-PKG"))
      (tycl:extract-type-from-form
       (let ((*readtable* tycl/reader:*tycl-readtable*))
         (read-from-string "(defgeneric [area :float] ([shape shape]))"))))
    (let ((info (tycl:lookup-type-info "TEST-PKG" "AREA")))
      (ok info "should register type info")
      (ok (typep info 'tycl:generic-function-type-info)
          "should be generic-function-type-info")
      (ok (eq (tycl:function-return-type info) :float)
          "return type should be :float")
      (ok (= (length (tycl:function-params info)) 1)
          "should have 1 parameter"))))

(deftest test-defgeneric-without-annotation
  (testing "defgeneric without type annotation uses default :t"
    (tycl:clear-type-database)
    (let ((tycl:*current-package* "TEST-PKG"))
      (tycl:extract-type-from-form
       (let ((*readtable* tycl/reader:*tycl-readtable*))
         (read-from-string "(defgeneric area (shape))"))))
    (let ((info (tycl:lookup-type-info "TEST-PKG" "AREA")))
      (ok info "should register type info")
      (ok (typep info 'tycl:generic-function-type-info))
      (ok (eq (tycl:function-return-type info) :t)))))

;;; ============================================================
;;; Transpilation Tests
;;; ============================================================

(deftest test-defgeneric-transpile
  (testing "defgeneric type annotations are stripped during transpilation"
    (let ((result (tycl:transpile-string
                   "(defgeneric [area :float] ([shape shape]))")))
      (ok (search "defgeneric" result) "should contain defgeneric")
      (ok (not (search "[" result)) "should not contain brackets")
      (ok (search "area" result) "should contain function name")
      (ok (search "shape" result) "should contain parameter name"))))

(deftest test-defgeneric-with-defmethod-transpile
  (testing "defgeneric and defmethod transpile correctly together"
    (let ((result (tycl:transpile-string
                   "(defgeneric [area :float] ([shape shape]))
                    (defmethod [area :float] ([shape circle])
                      (* 3.14 (slot-value shape 'radius)))")))
      (ok (search "defgeneric" result))
      (ok (search "defmethod" result))
      (ok (not (search "[" result))))))

;;; ============================================================
;;; Type Checking Tests
;;; ============================================================

(deftest test-defgeneric-valid
  (testing "Valid defgeneric passes type check"
    (multiple-value-bind (errors result)
        (check-and-get-errors
         "(defgeneric [area :float] ([shape shape]))")
      (ok result "should pass")
      (ok (null errors) "should have no errors"))))

(deftest test-defgeneric-with-matching-defmethod
  (testing "defmethod with matching return type passes"
    (multiple-value-bind (errors result)
        (check-and-get-errors
         "(defclass shape () ())
          (defclass circle (shape) (([radius :float])))
          (defgeneric [area :float] ([shape shape]))
          (defmethod [area :float] ([shape circle])
            (* 3.14 (slot-value shape 'radius)))")
      (ok result "should pass")
      (ok (null errors) "should have no errors"))))

(deftest test-defmethod-return-type-mismatch
  (testing "defmethod with incompatible return type produces error"
    (multiple-value-bind (errors result)
        (check-and-get-errors
         "(defclass shape () ())
          (defclass circle (shape) ())
          (defgeneric [area :float] ([shape shape]))
          (defmethod [area :string] ([shape circle])
            \"not a number\")")
      (ng result "should fail")
      (ok (not (null errors)) "should have errors")
      (ok (search "incompatible" (tycl/type-checker:error-message (first errors)))
          "error should mention incompatibility"))))

(deftest test-defmethod-wrong-param-count
  (testing "defmethod with wrong parameter count produces error"
    (multiple-value-bind (errors result)
        (check-and-get-errors
         "(defgeneric [move :void] ([shape shape] [dx :float] [dy :float]))
          (defmethod [move :void] ([shape circle] [dx :float])
            nil)")
      (ng result "should fail")
      (ok (not (null errors)) "should have errors")
      (ok (search "parameter" (tycl/type-checker:error-message (first errors)))
          "error should mention parameters"))))

(deftest test-defmethod-invalid-specializer
  (testing "defmethod with specializer not subtype of defgeneric param produces error"
    (multiple-value-bind (errors result)
        (check-and-get-errors
         "(defclass shape () ())
          (defclass color () (([name :string])))
          (defgeneric [area :float] ([shape shape]))
          (defmethod [area :float] ([shape color])
            0.0)")
      (ng result "should fail")
      (ok (not (null errors)) "should have errors")
      (ok (search "subtype" (tycl/type-checker:error-message (first errors)))
          "error should mention subtype"))))

(deftest test-defgeneric-call-type-inference
  (testing "Calling defgeneric function infers correct return type"
    (multiple-value-bind (errors result)
        (check-and-get-errors
         "(defclass shape () ())
          (defgeneric [area :float] ([shape shape]))
          (defun [total-area :float] ([s shape])
            (area s))")
      (ok result "should pass")
      (ok (null errors) "should have no errors"))))

(deftest test-defgeneric-call-type-mismatch
  (testing "Using defgeneric return type in wrong context produces error"
    (multiple-value-bind (errors result)
        (check-and-get-errors
         "(defclass shape () ())
          (defgeneric [area :float] ([shape shape]))
          (defun [describe-area :string] ([s shape])
            (area s))")
      (ng result "should fail")
      (ok (not (null errors)) "should have errors"))))

(deftest test-defgeneric-multi-level-subtype
  (testing "defmethod with multi-level subtype passes"
    (multiple-value-bind (errors result)
        (check-and-get-errors
         "(defclass a () ())
          (defclass b (a) ())
          (defclass c (b) ())
          (defgeneric [process :t] ([obj a]))
          (defmethod [process :t] ([obj c])
            obj)")
      (ok result "should pass")
      (ok (null errors) "should have no errors"))))

;;; ============================================================
;;; Serialization Tests
;;; ============================================================

(deftest test-defgeneric-serialization
  (testing "defgeneric type info serializes and deserializes correctly"
    (tycl:clear-type-database)
    (let ((tycl:*current-package* "TEST-PKG"))
      (tycl:extract-type-from-form
       (let ((*readtable* tycl/reader:*tycl-readtable*))
         (read-from-string "(defgeneric [area :float] ([shape shape]))"))))
    (let* ((info (tycl:lookup-type-info "TEST-PKG" "AREA"))
           (serialized (tycl::serialize-type-info info)))
      (ok (eq (first serialized) :generic-function)
          "serialized kind should be :generic-function")
      ;; Deserialize and verify
      (tycl:clear-type-database)
      (tycl::deserialize-type-info "TEST-PKG" serialized)
      (let ((restored (tycl:lookup-type-info "TEST-PKG" "AREA")))
        (ok restored "should restore from serialized form")
        (ok (typep restored 'tycl:generic-function-type-info)
            "restored should be generic-function-type-info")
        (ok (eq (tycl:function-return-type restored) :float)
            "restored return type should be :float")))))

;;; ============================================================
;;; defmethod without defgeneric Tests
;;; ============================================================

(deftest test-defmethod-without-defgeneric-different-specializers
  (testing "Multiple defmethods without defgeneric with different specializers pass"
    (multiple-value-bind (errors result)
        (check-and-get-errors
         "(defclass foo () ())
          (defclass bar () ())
          (defmethod [show :void] ([obj foo])
            (format t \"foo~%\"))
          (defmethod [show :void] ([obj bar])
            (format t \"bar~%\"))")
      (ok result "should pass")
      (ok (null errors) "should have no errors"))))

(deftest test-defmethod-without-defgeneric-call
  (testing "Calling defmethod-only generic function works"
    (multiple-value-bind (errors result)
        (check-and-get-errors
         "(defclass foo () ())
          (defclass bar () ())
          (defmethod [show :void] ([obj foo])
            (format t \"foo~%\"))
          (defmethod [show :void] ([obj bar])
            (format t \"bar~%\"))
          (defun [demo :void] ([f foo] [b bar])
            (show f)
            (show b))")
      (ok result "should pass")
      (ok (null errors) "should have no errors"))))

(deftest test-defmethod-without-defgeneric-param-count-mismatch
  (testing "defmethod with different param count produces error"
    (multiple-value-bind (errors result)
        (check-and-get-errors
         "(defmethod [show :void] ([p1 :integer] [p2 :integer])
            (format t \"result:~A~%\" (+ p1 p2)))
          (defmethod [show :void] ([p1 :integer])
            (format t \"result:~A~%\" p1))")
      (ng result "should fail")
      (ok (not (null errors)) "should have errors")
      (ok (search "parameter" (tycl/type-checker:error-message (first errors)))
          "error should mention parameters"))))

(deftest test-defmethod-without-defgeneric-auto-creates-generic-info
  (testing "Two defmethods auto-create a generic-function-type-info"
    (tycl:clear-type-database)
    (let ((tycl:*current-package* "TEST-PKG"))
      (dolist (form-str '("(defclass foo () ())"
                          "(defclass bar () ())"
                          "(defmethod [show :void] ([obj foo]) nil)"
                          "(defmethod [show :void] ([obj bar]) nil)"))
        (tycl:extract-type-from-form
         (let ((*readtable* tycl/reader:*tycl-readtable*))
           (read-from-string form-str)))))
    (let ((info (tycl:lookup-type-info "TEST-PKG" "SHOW")))
      (ok info "should have type info")
      (ok (typep info 'tycl:generic-function-type-info)
          "should be auto-created generic-function-type-info")
      (ok (= (length (tycl:generic-function-methods info)) 2)
          "should have 2 methods"))))

(deftest test-defmethod-without-defgeneric-transpile
  (testing "defmethod without defgeneric transpiles with specializers"
    (let ((result (tycl:transpile-string
                   "(defclass foo () ())
                    (defmethod [show :void] ([obj foo])
                      (format t \"foo~%\"))")))
      (ok (search "defmethod" result) "should contain defmethod")
      (ok (search "(obj foo)" result) "should preserve specializer"))))
