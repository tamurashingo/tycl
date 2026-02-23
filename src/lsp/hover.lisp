(in-package :tycl.lsp)

;;; Hover - Type Information Display

(defun extract-symbol-at-position (text line character)
  "Extract symbol name at the given position"
  (let* ((lines (split-string text #\Newline))
         (target-line (if (< line (length lines))
                         (nth line lines)
                         "")))
    (when (< character (length target-line))
      (let* ((start (or (position-if-not #'symbol-char-p target-line
                                        :end character
                                        :from-end t)
                       -1))
             (end (or (position-if-not #'symbol-char-p target-line
                                      :start character)
                     (length target-line))))
        (when (< (1+ start) end)
          (string-upcase (subseq target-line (1+ start) end)))))))

(defun symbol-char-p (char)
  "Check if character is valid in a symbol name"
  (or (alphanumericp char)
      (find char "-_*+/<>=!?&")))

(defun split-string (string delimiter)
  "Split string by delimiter"
  (loop with start = 0
        for pos = (position delimiter string :start start)
        collect (subseq string start (or pos (length string)))
        while pos
        do (setf start (1+ pos))))

(defun format-type-spec (type-spec)
  "Format type specification for display"
  (cond
    ((keywordp type-spec)
     (format nil "~(~A~)" type-spec))
    ((consp type-spec)
     (if (keywordp (car type-spec))
         ;; Generic type
         (format nil "~(~A~)<~{~A~^, ~}>"
                (car type-spec)
                (mapcar #'format-type-spec (cdr type-spec)))
         ;; Union type
         (format nil "~{~A~^ | ~}"
                (mapcar #'format-type-spec type-spec))))
    (t (format nil "~A" type-spec))))

(defun format-function-signature (info)
  "Format function type signature for hover display"
  (let ((type-spec (type-info-type-spec info)))
    (if (and (consp type-spec)
            (eq (car type-spec) :function))
        (let ((params (second type-spec))
              (return-type (third type-spec)))
          (format nil "```commonlisp~%(defun ~A (~{~A~^ ~}) -> ~A)~%```"
                 (type-info-name info)
                 (mapcar #'format-type-spec params)
                 (format-type-spec return-type)))
        (format nil "```commonlisp~%(defun ~A ...)~%```"
               (type-info-name info)))))

(defun format-value-info (info)
  "Format value type information for hover display"
  (format nil "```commonlisp~%(defvar ~A ~A)~%```"
         (type-info-name info)
         (format-type-spec (type-info-type-spec info))))

(defun format-class-info (info)
  "Format class information for hover display"
  (format nil "```commonlisp~%(defclass ~A ...)~%```"
         (type-info-name info)))

(defun format-hover-content (info)
  "Format type information for hover display"
  (case (type-info-kind info)
    (:function (format-function-signature info))
    (:value (format-value-info info))
    (:class (format-class-info info))
    (:method (format-function-signature info))
    (otherwise (format nil "Symbol: ~A" (type-info-name info)))))

(defun get-hover-info (uri line character)
  "Get hover information for position in document"
  (let* ((text (gethash uri *open-documents*))
         (symbol-name (and text (extract-symbol-at-position text line character))))
    (when symbol-name
      (let ((info (query-type-info symbol-name)))
        (when info
          `((:contents . ((:kind . "markdown")
                         (:value . ,(format-hover-content info))))
            (:range . ((:start . ((:line . ,line) (:character . 0)))
                       (:end . ((:line . ,line) (:character . 100)))))))))))
