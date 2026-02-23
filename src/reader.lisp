;;;; TyCL Reader
;;;; Read macro for [symbol type] notation

(in-package #:tycl/reader)

;;; TyCL readtable with bracket notation
(defvar *tycl-readtable* (copy-readtable nil)
  "Readtable with TyCL bracket notation enabled")

(defvar *original-readtable* (copy-readtable nil)
  "Backup of the original readtable")

(defun read-bracket-annotation (stream char)
  "Read [symbol type] and return a type-annotation instance"
  (declare (ignore char))
  (let ((contents (read-delimited-list #\] stream t)))
    (cond
      ;; [symbol type]
      ((and contents (= (length contents) 2))
       (make-type-annotation (first contents) (second contents)))
      ;; Empty or invalid
      (t (error "Invalid bracket annotation: ~S" contents)))))

;; Set up the readtable
(set-macro-character #\[ #'read-bracket-annotation nil *tycl-readtable*)
(set-syntax-from-char #\] #\) *tycl-readtable*)

(defun enable-tycl-reader ()
  "Enable TyCL bracket notation by switching to TyCL readtable"
  (setf *original-readtable* *readtable*)
  (setf *readtable* *tycl-readtable*)
  t)

(defun disable-tycl-reader ()
  "Disable TyCL bracket notation by restoring original readtable"
  (setf *readtable* *original-readtable*)
  t)
