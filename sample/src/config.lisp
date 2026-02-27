;;;; Sample Project - Configuration

(in-package #:cl-user)
(defpackage #:sample-project/config
  (:use #:cl)
  (:export #:*app-name*
           #:*version*
           #:*max-items*))
(in-package #:sample-project/config)

(defvar *app-name* "Sample TyCL App"
  "Application name")

(defvar *version* "1.0.0"
  "Application version")

(defvar *max-items* 100
  "Maximum number of items")

