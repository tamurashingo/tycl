;;;; TyCL Package Definitions
;;;; Defines all packages used in the TyCL system

(in-package #:cl-user)

(defpackage #:tycl/annotation
  (:use #:cl)
  (:export #:type-annotation
           #:type-annotation-p
           #:annotation-symbol
           #:annotation-type
           #:make-type-annotation))

(defpackage #:tycl/reader
  (:use #:cl #:tycl/annotation)
  (:export #:*tycl-readtable*
           #:enable-tycl-reader
           #:disable-tycl-reader))

(defpackage #:tycl/transpiler
  (:use #:cl #:tycl/annotation #:tycl/reader)
  (:export #:transpile-form
           #:transpile-string
           #:transpile-file))

(defpackage #:tycl/type-checker
  (:use #:cl #:tycl/annotation #:tycl/reader)
  (:export #:check-file
           #:check-string
           #:*type-check-errors*
           #:*enable-type-checking*))

(defpackage #:tycl
  (:use #:cl)
  (:import-from #:tycl/transpiler
                #:transpile-form
                #:transpile-string
                #:transpile-file)
  (:import-from #:tycl/type-checker
                #:check-file
                #:check-string
                #:*enable-type-checking*)
  (:import-from #:tycl/reader
                #:enable-tycl-reader
                #:disable-tycl-reader)
  (:export ;; Transpiler (re-export from tycl/transpiler)
           #:transpile-form
           #:transpile-string
           #:transpile-file
           ;; Type checker (re-export from tycl/type-checker)
           #:check-file
           #:check-string
           #:*enable-type-checking*
           ;; Reader (re-export from tycl/reader)
           #:enable-tycl-reader
           #:disable-tycl-reader
           ;; Loader
           #:load-tycl
           #:compile-and-load-tycl
           ;; Type info data structures
           #:type-info
           #:type-info-package
           #:type-info-symbol
           #:value-type-info
           #:value-type-spec
           #:function-type-info
           #:function-params
           #:function-return-type
           #:method-type-info
           #:method-specializers
           #:class-type-info
           #:class-slots
           #:class-superclasses
           #:type-database
           #:*type-database*
           #:register-type-info
           #:lookup-type-info
           #:get-type-info
           #:get-package-symbols
           #:clear-type-database
           ;; Type serialization
           #:save-package-types
           #:load-package-types
           #:write-type-database
           #:load-type-database
           ;; Type extraction
           #:extract-type-from-form
           #:*current-package*
           #:*current-file*
           #:register-type-extractor
           #:unregister-type-extractor
           #:find-type-extractor
           #:find-and-load-hooks
           #:load-hook-configuration
           #:clear-hook-configuration
           ;; Hooks loading
           #:load-tycl-hooks
           ;; LSP integration
           #:serialize-type-database-json
           #:save-type-database-json
           #:get-symbol-type
           #:find-functions-by-return-type
           #:find-functions-with-param-type
           #:get-class-hierarchy
           #:get-methods-for-class
           #:get-completion-items
           #:get-hover-info
           #:check-file-diagnostics))
