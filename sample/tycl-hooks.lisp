;;;; TyCL Hooks - Type Extractor Registration for Custom Macros
;;;; This file is automatically loaded by find-and-load-hooks during transpilation.

;; Ensure the macros package exists for symbol references below.
;; During ASDF compilation, macros.lisp is loaded first so this is a no-op.
;; During standalone type checking, this creates a minimal package stub.
(unless (find-package "SAMPLE-PROJECT/MACROS")
  (defpackage #:sample-project/macros
    (:export #:defmodel #:define-api)))

(in-package #:tycl)

;; defmodel hook: register class info + accessor method info
;; Syntax: (defmodel name ((slot-name type) ...))
;; Uses macro-specific syntax for type info (not TyCL's [] notation)
(register-type-extractor 'sample-project/macros:defmodel
  :type-extractor
    (lambda (form)
      (let* ((name (second form))
             (slot-specs (third form))
             (class-name-str (string-upcase (symbol-name name))))
        ;; Class info + accessor method info
        (cons
         `(:kind :class
           :symbol ,name
           :slots ,(loop for spec in slot-specs
                         collect (list :name (string-upcase (symbol-name (first spec)))
                                       :type (second spec))))
         ;; Accessor method info (user-name, user-age, etc.)
         (loop for spec in slot-specs
               collect `(:kind :function
                         :symbol ,(format nil "~A-~A"
                                          class-name-str
                                          (string-upcase (symbol-name (first spec))))
                         :params ((:name "SELF" :type ,name))
                         :return ,(second spec)))))))

;; define-api hook: register function type info
;; Syntax: (define-api [name return-type] ([param type] ...) body...)
;; name and params use TyCL's [] annotation syntax
(register-type-extractor 'sample-project/macros:define-api
  :type-extractor
    (lambda (form)
      (let* ((name-spec (second form))
             (params-spec (third form))
             (name (if (tycl/annotation:type-annotation-p name-spec)
                       (tycl/annotation:annotation-symbol name-spec)
                       name-spec))
             (return-type (if (tycl/annotation:type-annotation-p name-spec)
                              (tycl/annotation:annotation-type name-spec)
                              :t))
             (params (loop for p in params-spec
                           collect (if (tycl/annotation:type-annotation-p p)
                                       (list :name (string-upcase
                                                     (symbol-name
                                                      (tycl/annotation:annotation-symbol p)))
                                             :type (tycl/annotation:annotation-type p))
                                       (list :name (string-upcase (symbol-name p))
                                             :type :t)))))
        (list
         `(:kind :function
           :symbol ,name
           :params ,params
           :return ,return-type)))))
