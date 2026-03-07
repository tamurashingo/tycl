;;;; Sample Project - Package Definitions

(defpackage #:sample-project/math
  (:use #:cl)
  (:export #:add
           #:multiply
           #:factorial
           #:safe-divide))

(defpackage #:sample-project/string-utils
  (:use #:cl)
  (:export #:join-strings
           #:repeat-string
           #:truncate-string))

(defpackage #:sample-project/config
  (:use #:cl)
  (:export #:*app-name*
           #:*version*
           #:*max-items*))

(defpackage #:sample-project/collections
  (:use #:cl)
  (:export #:identity-fn
           #:wrap
           #:first-or-default
           #:swap-pair
           #:apply-twice
           #:zip-lists))

(defpackage #:sample-project/main
  (:use #:cl
        #:sample-project/math
        #:sample-project/string-utils
        #:sample-project/config
        #:sample-project/collections)
  (:export #:format-result
           #:describe-app
           #:run))
