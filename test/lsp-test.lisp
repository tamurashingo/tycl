;;;; lsp-test.lisp
;;;; Tests for LSP integration features

(defpackage :tycl/test/lsp
  (:use :cl :rove)
  (:import-from :tycl
                :register-type-info
                :value-type-info
                :function-type-info
                :method-type-info
                :class-type-info
                :clear-type-database
                :get-symbol-type
                :get-package-symbols
                :find-functions-by-return-type
                :find-functions-with-param-type
                :get-class-hierarchy
                :get-methods-for-class
                :get-completion-items
                :get-hover-info
                :serialize-type-database-json
                :save-type-database-json))

(in-package :tycl/test/lsp)

(deftest query-api-tests
  (testing "get-symbol-type"
    (clear-type-database)
    
    ;; Register test data
    (register-type-info 
     (make-instance 'value-type-info
                    :package "TEST-PACKAGE"
                    :symbol "MY-VAR"
                    :type-spec :integer))
    
    (register-type-info
     (make-instance 'function-type-info
                    :package "TEST-PACKAGE"
                    :symbol "MY-FUNC"
                    :params '((:name "X" :type-spec :integer)
                             (:name "Y" :type-spec :integer))
                    :return-type :integer))
    
    ;; Test retrieval
    (let ((var-info (get-symbol-type "MY-VAR" "TEST-PACKAGE"))
          (func-info (get-symbol-type "MY-FUNC" "TEST-PACKAGE")))
      (ok var-info "Should find variable")
      (ok func-info "Should find function")
      (ok (equal (tycl::type-info-kind var-info) :value))
      (ok (equal (tycl::type-info-kind func-info) :function))))
  
  (testing "get-package-symbols"
    (clear-type-database)
    
    ;; Register test data in multiple packages
    (register-type-info 
     (make-instance 'value-type-info
                    :package "PKG-A"
                    :symbol "VAR-1"
                    :type-spec :integer))
    
    (register-type-info 
     (make-instance 'value-type-info
                    :package "PKG-A"
                    :symbol "VAR-2"
                    :type-spec :string))
    
    (register-type-info 
     (make-instance 'value-type-info
                    :package "PKG-B"
                    :symbol "VAR-3"
                    :type-spec :float))
    
    ;; Test retrieval
    (let ((pkg-a-symbols (get-package-symbols "PKG-A"))
          (pkg-b-symbols (get-package-symbols "PKG-B")))
      (ok (= (length pkg-a-symbols) 2) "Should find 2 symbols in PKG-A")
      (ok (= (length pkg-b-symbols) 1) "Should find 1 symbol in PKG-B")))
  
  (testing "find-functions-by-return-type"
    (clear-type-database)
    
    ;; Register functions with different return types
    (register-type-info
     (make-instance 'function-type-info
                    :package "TEST"
                    :symbol "GET-NUM"
                    :params '()
                    :return-type :integer))
    
    (register-type-info
     (make-instance 'function-type-info
                    :package "TEST"
                    :symbol "GET-STR"
                    :params '()
                    :return-type :string))
    
    (register-type-info
     (make-instance 'function-type-info
                    :package "TEST"
                    :symbol "ADD"
                    :params '((:name "X" :type-spec :integer) (:name "Y" :type-spec :integer))
                    :return-type :integer))
    
    ;; Test search
    (let ((int-funcs (find-functions-by-return-type :integer))
          (str-funcs (find-functions-by-return-type :string)))
      (ok (= (length int-funcs) 2) "Should find 2 integer-returning functions")
      (ok (= (length str-funcs) 1) "Should find 1 string-returning function")))
  
  (testing "find-functions-with-param-type"
    (clear-type-database)
    
    ;; Register functions
    (register-type-info
     (make-instance 'function-type-info
                    :package "TEST"
                    :symbol "PROCESS-INT"
                    :params '((:name "X" :type :integer))
                    :return-type :string))
    
    (register-type-info
     (make-instance 'function-type-info
                    :package "TEST"
                    :symbol "PROCESS-STR"
                    :params '((:name "S" :type :string))
                    :return-type :integer))
    
    (register-type-info
     (make-instance 'function-type-info
                    :package "TEST"
                    :symbol "ADD"
                    :params '((:name "X" :type :integer) (:name "Y" :type :integer))
                    :return-type :integer))
    
    ;; Test search
    (let ((int-param-funcs (find-functions-with-param-type :integer))
          (str-param-funcs (find-functions-with-param-type :string)))
      (ok (= (length int-param-funcs) 2) "Should find 2 functions accepting integer")
      (ok (= (length str-param-funcs) 1) "Should find 1 function accepting string")))
  
  (testing "get-class-hierarchy"
    (clear-type-database)
    
    ;; Register class hierarchy
    (register-type-info
     (make-instance 'class-type-info
                    :package "TEST"
                    :symbol "ANIMAL"
                    :slots '((:name "NAME" :type :string))
                    :superclasses '()))
    
    (register-type-info
     (make-instance 'class-type-info
                    :package "TEST"
                    :symbol "DOG"
                    :slots '((:name "BREED" :type :string))
                    :superclasses '(animal)))
    
    ;; Test hierarchy
    (let ((hierarchy (get-class-hierarchy "ANIMAL" "TEST")))
      (ok hierarchy "Should get class hierarchy")
      (ok (member "DOG" (getf hierarchy :subclasses) :test #'string-equal)
          "DOG should be subclass of ANIMAL")))
  
  (testing "get-methods-for-class"
    (clear-type-database)
    
    ;; Register class and methods
    (register-type-info
     (make-instance 'class-type-info
                    :package "TEST"
                    :symbol "USER"
                    :slots '((:name "NAME" :type :string))
                    :superclasses '()))
    
    (register-type-info
     (make-instance 'method-type-info
                    :package "TEST"
                    :symbol "GREET"
                    :params '((:name "U" :type user :specializer user))
                    :return-type :string))
    
    (register-type-info
     (make-instance 'method-type-info
                    :package "TEST"
                    :symbol "DESCRIBE"
                    :params '((:name "U" :type user :specializer user))
                    :return-type :string))
    
    ;; Test method search
    (let ((methods (get-methods-for-class "USER")))
      (ok (= (length methods) 2) "Should find 2 methods for USER class"))))

(deftest completion-and-hover-tests
  (testing "get-completion-items"
    (clear-type-database)
    
    ;; Register test symbols
    (register-type-info
     (make-instance 'function-type-info
                    :package "TEST"
                    :symbol "MY-ADD"
                    :params '((:name "X" :type-spec :integer) (:name "Y" :type-spec :integer))
                    :return-type :integer))
    
    (register-type-info
     (make-instance 'function-type-info
                    :package "TEST"
                    :symbol "MY-SUBTRACT"
                    :params '((:name "X" :type-spec :integer) (:name "Y" :type-spec :integer))
                    :return-type :integer))
    
    (register-type-info
     (make-instance 'value-type-info
                    :package "TEST"
                    :symbol "OTHER-VAR"
                    :type-spec :string))
    
    ;; Test completion
    (let ((my-completions (get-completion-items "MY" "TEST"))
          (all-completions (get-completion-items "" "TEST")))
      (ok (>= (length my-completions) 2) "Should find at least 2 MY-* completions")
      (ok (>= (length all-completions) 3) "Should find at least 3 total completions")))
  
  (testing "get-hover-info"
    (clear-type-database)
    
    ;; Register test symbol
    (register-type-info
     (make-instance 'function-type-info
                    :package "TEST"
                    :symbol "MY-FUNC"
                    :params '((:name "X" :type-spec :integer))
                    :return-type :string))
    
    ;; Test hover
    (let ((hover (get-hover-info "MY-FUNC" "TEST")))
      (ok hover "Should get hover info")
      (ok (assoc :contents hover) "Should have contents"))))

(deftest json-serialization-tests
  (testing "serialize-type-database-json"
    (clear-type-database)
    
    ;; Register test data
    (register-type-info
     (make-instance 'value-type-info
                    :package "TEST"
                    :symbol "MY-VAR"
                    :type-spec :integer))
    
    (register-type-info
     (make-instance 'function-type-info
                    :package "TEST"
                    :symbol "MY-FUNC"
                    :params '((:name "X" :type-spec :integer))
                    :return-type :string))
    
    ;; Test serialization
    (let ((json-data (serialize-type-database-json)))
      (ok json-data "Should serialize to JSON")
      (ok (assoc :version json-data) "Should have version")
      (ok (assoc :entries json-data) "Should have entries")
      (ok (>= (length (cdr (assoc :entries json-data))) 2)
          "Should have at least 2 entries")))
  
  (testing "save-type-database-json"
    (clear-type-database)
    
    ;; Register test data
    (register-type-info
     (make-instance 'value-type-info
                    :package "TEST"
                    :symbol "TEST-VAR"
                    :type-spec :integer))
    
    ;; Save to temporary file
    (let ((temp-file (merge-pathnames "test-output.json" 
                                     (asdf:system-relative-pathname :tycl "test/"))))
      (unwind-protect
          (progn
            (save-type-database-json temp-file)
            (ok (probe-file temp-file) "JSON file should be created"))
        ;; Cleanup
        (when (probe-file temp-file)
          (delete-file temp-file))))))

(deftest type-to-json-tests
  (testing "type-to-json for simple types"
    (ok (string= (tycl::type-to-json :integer) "integer"))
    (ok (string= (tycl::type-to-json :string) "string")))
  
  (testing "type-to-json for union types"
    (let ((result (tycl::type-to-json '(:integer :string))))
      (ok (assoc :type result))
      (ok (string= (cdr (assoc :type result)) "union"))
      (ok (assoc :types result))))
  
  (testing "type-to-json for generic types"
    (let ((result (tycl::type-to-json '(:list (:integer)))))
      (ok (assoc :type result))
      (ok (string= (cdr (assoc :type result)) "generic"))
      (ok (assoc :base result))
      (ok (string= (cdr (assoc :base result)) "list"))
      (ok (assoc :params result)))))
