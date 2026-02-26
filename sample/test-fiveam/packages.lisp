(in-package #:cl-user)
(defpackage #:sample-project/test-fiveam
  (:use #:cl #:fiveam)
  (:export #:run-tests))
(in-package #:sample-project/test-fiveam)

(def-suite sample-project-suite
  :description "Sample Project test suite")

(defun run-tests ()
  (run! 'sample-project-suite))
