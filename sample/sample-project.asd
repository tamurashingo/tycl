;;;; sample project

(in-package #:cl-user)
(defpackage #:sample-project-system
  (:use #:asdf #:cl))
(in-package #:sample-project-system)

;; Forward declaration: create a stub tycl/asdf package so the reader
;; can resolve tycl/asdf:tycl-system before tycl is loaded.
;; The real definitions are provided when :defsystem-depends-on loads tycl.
(unless (find-package :tycl/asdf)
  (defpackage #:tycl/asdf
    (:export #:tycl-system #:tycl-file)))

(defsystem sample-project
  :version "0.0.1"
  :class tycl/asdf:tycl-system
  :defsystem-depends-on (#:tycl)
  :tycl-output-dir "build/"
  :tycl-extract-types t
  :tycl-save-types t
  :components ((:module "src"
                :serial t
                :components
                ((:tycl-file "math")
                 (:tycl-file "string-utils")
                 (:tycl-file "collections")
                 (:file "config")
                 (:tycl-file "main"))))
  :in-order-to ((test-op (test-op "sample-project/test-rove"))))

(defsystem sample-project/test-rove
  :class tycl/asdf:tycl-system
  :defsystem-depends-on (#:tycl)
  :tycl-extract-types t
  :tycl-save-types t
  :depends-on ("sample-project" "rove")
  :components ((:module "test-rove"
                :serial t
                :components
                ((:tycl-file "config")
                 (:tycl-file "math")
                 (:tycl-file "string-utils")
                 (:tycl-file "collections"))))
  :perform (test-op (op c)
             (uiop:symbol-call :rove :run c)))

(defsystem sample-project/test-fiveam
  :class tycl/asdf:tycl-system
  :defsystem-depends-on (#:tycl)
  :tycl-output-dir "build/"
  :tycl-extract-types t
  :tycl-save-types t
  :depends-on ("sample-project" "fiveam")
  :components ((:module "test-fiveam"
                :serial t
                :components
                ((:file "packages")
                 (:tycl-file "math")
                 (:tycl-file "string-utils")
                 (:tycl-file "collections")
                 (:file "config"))))
  :perform (test-op (op c)
             (declare (ignore op c))
             (uiop:symbol-call :sample-project/test-fiveam :run-tests)))
