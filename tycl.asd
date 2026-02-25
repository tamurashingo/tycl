;;;; Copyright 2026 tamura shingo
;;;;
;;;; MIT License

(in-package #:cl-user)

(defpackage #:tycl-system
  (:use #:asdf #:cl))

(in-package #:tycl-system)

(defsystem tycl
  :version "0.0.1"
  :author "tamura shingo"
  :license "MIT"
  :description "TyCL - Typed Common Lisp: Gradual typing for Common Lisp with LSP support"
  :depends-on (#:cl-ppcre #:cl-json #:babel)
  :components ((:module "src"
                :serial t
                :components
                ((:file "packages")
                 (:file "annotation")
                 (:file "reader")
                 (:file "type-info")
                 (:file "type-serializer")
                 (:file "type-extractor")
                 (:file "transpiler")
                 (:file "type-checker")
                 (:file "lsp-integration")
                 (:file "main")))
               (:module "src/lsp"
                :serial t
                :components
                ((:file "packages")
                 (:file "protocol")
                 (:file "cache")
                 (:file "diagnostics")
                 (:file "hover")
                 (:file "completion")
                 (:file "handlers")
                 (:file "server"))))
  
  :in-order-to ((test-op (test-op "tycl/test"))))

(defsystem tycl/test
  :author "tamura shingo"
  :license "MIT"
  :description "Test system for TyCL"
  :depends-on ("tycl" "rove")
  :components ((:module "test"
                :components
                ((:file "sample-test")
                 (:file "transpiler-test")
                 (:file "load-tycl-test")
                 (:file "hooks-test")
                 (:file "tycl-hooks-test")
                 (:file "sample-hook-test")
                 (:file "lsp-test")))
               (:module "test/lsp"
                :components
                ((:file "did-change-test"))))
  :perform (test-op (op c)
                    (declare (ignore op c))
                    (uiop:symbol-call :rove :run :tycl/test)))
