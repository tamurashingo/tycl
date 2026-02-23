;;;; Tests for TyCL Type Extraction Hooks

(defpackage #:tycl/test/hooks
  (:use #:cl #:rove))

(in-package #:tycl/test/hooks)

(deftest test-register-type-extractor
  (testing "Basic hook registration"
    ;; Clear any existing hooks
    (tycl:clear-hook-configuration)
    
    ;; Register a simple hook
    (tycl:register-type-extractor 'test-macro
      :type-extractor
        (lambda (form)
          (list `(:kind :function
                  :symbol ,(second form)
                  :params ()
                  :return :integer))))
    
    ;; Verify hook is registered
    (ok (tycl:find-type-extractor 'test-macro))
    
    ;; Clear hooks
    (tycl:clear-hook-configuration)))

(deftest test-single-type-extraction
  (testing "Hook that returns single type info"
    ;; Clear hooks
    (tycl:clear-hook-configuration)
    (tycl:clear-type-database)
    
    ;; Register a simple API hook
    (tycl:register-type-extractor 'test-defapi
      :type-extractor
        (lambda (form)
          ;; (test-defapi get-user :params ((id :integer)) :return :string)
          (let ((name (second form))
                (body (cddr form)))
            (list
             `(:kind :function
               :symbol ,name
               :params ,(mapcar (lambda (p)
                                 (list :name (symbol-name (first p))
                                       :type (second p)))
                               (getf body :params))
               :return ,(getf body :return))))))
    
    ;; Extract from a form
    (let ((tycl:*current-package* "TEST")
          (tycl:*current-file* "test.tycl"))
      (tycl:extract-type-from-form 
       '(test-defapi get-user :params ((id :integer)) :return :string)))
    
    ;; Verify type was registered
    (let ((info (tycl:get-type-info "TEST" "GET-USER")))
      (ok info)
      (ok (typep info 'tycl:function-type-info))
      (ok (equal (tycl:function-return-type info) :string)))
    
    ;; Clear
    (tycl:clear-hook-configuration)
    (tycl:clear-type-database)))

(deftest test-multiple-type-extraction
  (testing "Hook that returns multiple type infos"
    ;; Clear
    (tycl:clear-hook-configuration)
    (tycl:clear-type-database)
    
    ;; Register a model hook that creates class + constructor + predicate
    (tycl:register-type-extractor 'test-defmodel
      :type-extractor
        (lambda (form)
          ;; (test-defmodel person :slots ((name :string)) :constructor make-person :predicate person-p)
          (let* ((name (second form))
                 (body (cddr form))
                 (slots (getf body :slots))
                 (constructor (getf body :constructor))
                 (predicate (getf body :predicate)))
            (append
             ;; Class
             (list
              `(:kind :class
                :symbol ,name
                :slots ,(mapcar (lambda (slot)
                                 (list :name (symbol-name (first slot))
                                       :type (second slot)))
                               slots)))
             ;; Constructor
             (when constructor
               (list
                `(:kind :function
                  :symbol ,constructor
                  :params ,(mapcar (lambda (slot)
                                    (list :name (symbol-name (first slot))
                                          :type (second slot)))
                                  slots)
                  :return ,name)))
             ;; Predicate
             (when predicate
               (list
                `(:kind :function
                  :symbol ,predicate
                  :params ((:name "OBJ" :type :t))
                  :return :boolean)))))))
    
    ;; Extract from form
    (let ((tycl:*current-package* "TEST")
          (tycl:*current-file* "test.tycl"))
      (tycl:extract-type-from-form
       '(test-defmodel person 
         :slots ((name :string) (age :integer))
         :constructor make-person
         :predicate person-p)))
    
    ;; Verify class was registered
    (let ((class-info (tycl:get-type-info "TEST" "PERSON")))
      (ok class-info)
      (ok (typep class-info 'tycl:class-type-info)))
    
    ;; Verify constructor was registered
    (let ((ctor-info (tycl:get-type-info "TEST" "MAKE-PERSON")))
      (ok ctor-info)
      (ok (typep ctor-info 'tycl:function-type-info))
      (ok (equal (tycl:function-return-type ctor-info) 'person)))
    
    ;; Verify predicate was registered
    (let ((pred-info (tycl:get-type-info "TEST" "PERSON-P")))
      (ok pred-info)
      (ok (typep pred-info 'tycl:function-type-info))
      (ok (equal (tycl:function-return-type pred-info) :boolean)))
    
    ;; Clear
    (tycl:clear-hook-configuration)
    (tycl:clear-type-database)))

(deftest test-hook-file-loading
  (testing "Loading hooks from file"
    ;; Clear
    (tycl:clear-hook-configuration)
    
    ;; Create a temporary hook file
    (let ((temp-file (uiop:with-temporary-file (:pathname p :type "lisp" :keep t)
                       (with-open-file (out p :direction :output :if-exists :supersede)
                         (write-string 
                          "(in-package #:tycl)
(register-type-extractor 'temp-test-macro
  :type-extractor
    (lambda (form)
      (list `(:kind :value
              :symbol ,(second form)
              :type :integer))))"
                          out))
                       p)))
      (unwind-protect
           (progn
             ;; Load the hook file
             (tycl:load-hook-configuration temp-file)
             
             ;; Verify hook is registered (use fully qualified symbol)
             (ok (tycl:find-type-extractor (find-symbol "TEMP-TEST-MACRO" "TYCL")))
             
             ;; Try loading again - should not reload
             (ok (tycl:load-hook-configuration temp-file)))
        
        ;; Cleanup
        (when (probe-file temp-file)
          (delete-file temp-file))
        (tycl:clear-hook-configuration)))))
