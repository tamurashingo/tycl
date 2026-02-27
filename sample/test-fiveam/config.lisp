(in-package #:sample-project/test-fiveam)

(def-suite config-suite
  :in sample-project-suite
  :description "Config module tests")

(in-suite config-suite)

(test app-name-test
  (is (stringp sample-project/config:*app-name*)))

(test version-test
  (is (stringp sample-project/config:*version*)))

(test max-items-test
  (is (integerp sample-project/config:*max-items*))
  (is (plusp sample-project/config:*max-items*)))
