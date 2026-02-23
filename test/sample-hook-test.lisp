;;;; Sample Hook Test
;;;; Tests for custom type extractor hooks

(in-package #:cl-user)
(defpackage #:tycl/test/sample-hook
  (:use #:cl)
  (:import-from #:rove
                #:deftest
                #:testing
                #:ok))
(in-package #:tycl/test/sample-hook)

(deftest test-custom-hook-simple-class
  (testing "Custom hook for simple class definition"
    ;; Register a custom hook
    (tycl:register-type-extractor 'my-defclass
      :type-extractor
        (lambda (form)
          (list
           `(:kind :class
             :symbol ,(symbol-name (second form))
             :slots ,(mapcar (lambda (slot)
                              `(:name ,(symbol-name (first slot))
                                :type ,(second slot)))
                            (cddr form))))))
    
    ;; Clear database
    (tycl:clear-type-database)
    
    ;; Test form
    (let ((form '(my-defclass user
                  (name :string)
                  (age :integer))))
      (tycl::extract-type-from-form form)
      
      ;; Check if type info was registered
      (let ((info (tycl:get-type-info "COMMON-LISP-USER" "USER")))
        (ok (not (null info)))
        (ok (typep info 'tycl:class-type-info))
        (ok (equal (tycl:class-slots info)
                   '((:name "NAME" :type :string)
                     (:name "AGE" :type :integer))))))
    
    ;; Cleanup
    (tycl:unregister-type-extractor 'my-defclass)))

(deftest test-custom-hook-multiple-definitions
  (testing "Custom hook that defines multiple types"
    ;; Register a hook that defines both class and constructor
    (tycl:register-type-extractor 'defrecord
      :type-extractor
        (lambda (form)
          ;; (defrecord person (name :string) (age :integer))
          (let ((name (second form))
                (fields (cddr form)))
            (list
             ;; Class definition
             `(:kind :class
               :symbol ,(symbol-name name)
               :slots ,(mapcar (lambda (field)
                                `(:name ,(symbol-name (first field))
                                  :type ,(second field)))
                              fields))
             ;; Constructor function
             `(:kind :function
               :symbol ,(format nil "MAKE-~A" (symbol-name name))
               :params ,(mapcar (lambda (field)
                                 `(:name ,(symbol-name (first field))
                                   :type ,(second field)))
                               fields)
               :return ,name)))))
    
    ;; Clear database
    (tycl:clear-type-database)
    
    ;; Test form
    (let ((form '(defrecord person (name :string) (age :integer))))
      (tycl::extract-type-from-form form)
      
      ;; Check class
      (let ((class-info (tycl:get-type-info "COMMON-LISP-USER" "PERSON")))
        (ok (not (null class-info)))
        (ok (typep class-info 'tycl:class-type-info)))
      
      ;; Check constructor
      (let ((func-info (tycl:get-type-info "COMMON-LISP-USER" "MAKE-PERSON")))
        (ok (not (null func-info)))
        (ok (typep func-info 'tycl:function-type-info))
        (ok (= (length (tycl:function-params func-info)) 2))))
    
    ;; Cleanup
    (tycl:unregister-type-extractor 'defrecord)))

(deftest test-custom-hook-api-definition
  (testing "Custom hook for API definition"
    ;; Register a hook for API definitions
    (tycl:register-type-extractor 'defapi
      :type-extractor
        (lambda (form)
          (list
           `(:kind :function
             :symbol ,(symbol-name (second form))
             :params ,(getf (cddr form) :params)
             :return ,(getf (cddr form) :return)))))
    
    ;; Clear database
    (tycl:clear-type-database)
    
    ;; Test form
    (let ((form '(defapi get-user
                  :params ((:name "ID" :type :integer))
                  :return user)))
      (tycl::extract-type-from-form form)
      
      ;; Check if function was registered
      (let ((info (tycl:get-type-info "COMMON-LISP-USER" "GET-USER")))
        (ok (not (null info)))
        (ok (typep info 'tycl:function-type-info))
        (ok (= (length (tycl:function-params info)) 1))))
    
    ;; Cleanup
    (tycl:unregister-type-extractor 'defapi)))
