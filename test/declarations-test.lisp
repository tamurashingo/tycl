;;;; Tests for TyCL Declaration Files (.d.tycl)

(defpackage #:tycl/test/declarations
  (:use #:cl #:rove))

(in-package #:tycl/test/declarations)

(defun test-declarations-dir ()
  "Return the path to the test declarations directory"
  (merge-pathnames
   "test/declarations/"
   (asdf:system-source-directory :tycl)))

(deftest test-load-declaration-file
  (testing "Loading a single .d.tycl file"
    (tycl:clear-type-database)
    (tycl:clear-loaded-declarations)

    (let ((decl-file (merge-pathnames
                      "tycl-declarations/alexandria.d.tycl"
                      (test-declarations-dir))))
      ;; Load the declaration file
      (ok (tycl:load-declaration-file decl-file :output nil))

      ;; Verify types were registered
      (let ((flatten-info (tycl:get-type-info "ALEXANDRIA" "FLATTEN")))
        (ok flatten-info "flatten should be registered")
        (ok (typep flatten-info 'tycl:function-type-info))
        (ok (equal (tycl:function-return-type flatten-info) :list)))

      (let ((starts-info (tycl:get-type-info "ALEXANDRIA" "STARTS-WITH-SUBSEQ")))
        (ok starts-info "starts-with-subseq should be registered")
        (ok (equal (tycl:function-return-type starts-info) :boolean)))

      (let ((iota-info (tycl:get-type-info "ALEXANDRIA" "IOTA")))
        (ok iota-info "iota should be registered")
        (ok (equal (length (tycl:function-params iota-info)) 3))))

    (tycl:clear-type-database)
    (tycl:clear-loaded-declarations)))

(deftest test-load-declaration-file-idempotent
  (testing "Loading the same file twice does not duplicate"
    (tycl:clear-type-database)
    (tycl:clear-loaded-declarations)

    (let ((decl-file (merge-pathnames
                      "tycl-declarations/alexandria.d.tycl"
                      (test-declarations-dir))))
      (ok (tycl:load-declaration-file decl-file :output nil))
      ;; Second load should succeed (already loaded)
      (ok (tycl:load-declaration-file decl-file :output nil))

      ;; Types should still be there
      (ok (tycl:get-type-info "ALEXANDRIA" "FLATTEN")))

    (tycl:clear-type-database)
    (tycl:clear-loaded-declarations)))

(deftest test-load-declaration-file-not-found
  (testing "Loading a non-existent file returns NIL"
    (ok (not (tycl:load-declaration-file "/nonexistent/file.d.tycl" :output nil)))))

(deftest test-load-declarations-directory
  (testing "Loading all .d.tycl files from a directory"
    (tycl:clear-type-database)
    (tycl:clear-loaded-declarations)

    (let ((decl-dir (merge-pathnames
                     "tycl-declarations/"
                     (test-declarations-dir))))
      (let ((count (tycl:load-declarations-directory decl-dir :output nil)))
        (ok (>= count 2) "Should load at least 2 declaration files")))

    ;; Verify Alexandria types
    (ok (tycl:get-type-info "ALEXANDRIA" "FLATTEN"))
    (ok (tycl:get-type-info "ALEXANDRIA" "ENSURE-LIST"))

    ;; Verify CL-PPCRE types
    (ok (tycl:get-type-info "CL-PPCRE" "SCAN"))
    (ok (tycl:get-type-info "CL-PPCRE" "SPLIT"))

    (tycl:clear-type-database)
    (tycl:clear-loaded-declarations)))

(deftest test-load-declarations-directory-nonexistent
  (testing "Loading from non-existent directory returns 0"
    (ok (= 0 (tycl:load-declarations-directory "/nonexistent/dir/" :output nil)))))

(deftest test-find-and-load-declarations
  (testing "Auto-discovery of declaration files"
    (tycl:clear-type-database)
    (tycl:clear-loaded-declarations)

    ;; Use the test directory which has tycl-declarations/ subdirectory
    (let ((tycl:*declaration-search-paths* nil))  ; disable global paths
      (let ((count (tycl:find-and-load-declarations
                    (test-declarations-dir) :output nil)))
        (ok (>= count 2) "Should find and load declarations")))

    ;; Verify types from both files were loaded
    (ok (tycl:get-type-info "ALEXANDRIA" "FLATTEN"))
    (ok (tycl:get-type-info "CL-PPCRE" "SCAN"))

    (tycl:clear-type-database)
    (tycl:clear-loaded-declarations)))

(deftest test-declaration-with-defclass
  (testing "Declaration files can declare classes"
    (tycl:clear-type-database)
    (tycl:clear-loaded-declarations)

    ;; Create a temporary declaration file with a class
    (uiop:with-temporary-file (:pathname p :type "d.tycl" :keep t)
      (with-open-file (out p :direction :output :if-exists :supersede)
        (write-string
         "(defpackage #:test-ext (:use #:cl))
(in-package #:test-ext)
(defclass test-widget ()
  (([name :string] :initarg :name)
   ([width :integer] :initarg :width)
   ([height :integer] :initarg :height)))
(defun [make-widget test-widget] ([name :string] [width :integer] [height :integer]))"
         out))
      (unwind-protect
           (progn
             (ok (tycl:load-declaration-file p :output nil))

             ;; Verify class
             (let ((class-info (tycl:get-type-info "TEST-EXT" "TEST-WIDGET")))
               (ok class-info "class should be registered")
               (ok (typep class-info 'tycl:class-type-info))
               (ok (= 3 (length (tycl:class-slots class-info)))))

             ;; Verify constructor function
             (let ((func-info (tycl:get-type-info "TEST-EXT" "MAKE-WIDGET")))
               (ok func-info "constructor should be registered")
               (ok (typep func-info 'tycl:function-type-info))))
        (when (probe-file p)
          (delete-file p))))

    (tycl:clear-type-database)
    (tycl:clear-loaded-declarations)))

(deftest test-clear-loaded-declarations
  (testing "Clearing loaded declarations allows reloading"
    (tycl:clear-type-database)
    (tycl:clear-loaded-declarations)

    (let ((decl-file (merge-pathnames
                      "tycl-declarations/alexandria.d.tycl"
                      (test-declarations-dir))))
      (ok (tycl:load-declaration-file decl-file :output nil))
      (tycl:clear-loaded-declarations)
      ;; Should be able to load again after clearing
      (ok (tycl:load-declaration-file decl-file :output nil)))

    (tycl:clear-type-database)
    (tycl:clear-loaded-declarations)))
