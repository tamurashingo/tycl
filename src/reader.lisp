;;;; TyCL Reader
;;;; Read macro for [symbol type] notation

(in-package #:tycl/reader)

;;; TyCL readtable with bracket notation
(defvar *tycl-readtable* (copy-readtable nil)
  "Readtable with TyCL bracket notation enabled")

(defvar *original-readtable* (copy-readtable nil)
  "Backup of the original readtable")

(defun read-angle-type-params (stream char)
  "Read <T> or <A B> and return a type-params instance"
  (declare (ignore char))
  (let ((contents (read-delimited-list #\> stream t)))
    (unless contents
      (error "Empty type parameters: <>"))
    (unless (every #'symbolp contents)
      (error "Type parameters must be symbols: ~S" contents))
    (make-type-params :entries contents)))

(defun read-bracket-annotation (stream char)
  "Read [symbol type] or [symbol <type-params> type] and return a type-annotation instance"
  (declare (ignore char))
  (let ((*readtable* (copy-readtable *tycl-readtable*)))
    ;; Temporarily add < as a reader macro within brackets
    (set-macro-character #\< #'read-angle-type-params nil *readtable*)
    (set-syntax-from-char #\> #\) *readtable*)
    (let ((contents (read-delimited-list #\] stream t)))
      (cond
        ;; [symbol type] — normal 2-element annotation
        ((and contents (= (length contents) 2)
              (not (type-params-p (first contents)))
              (not (type-params-p (second contents))))
         (make-type-annotation (first contents) (second contents)))
        ;; [symbol <type-vars> type] — polymorphic 3-element annotation
        ((and contents (= (length contents) 3)
              (type-params-p (second contents)))
         (make-type-annotation (first contents) (third contents)
                               :type-params (second contents)))
        ;; Empty or invalid
        (t (error "Invalid bracket annotation: ~S" contents))))))

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
