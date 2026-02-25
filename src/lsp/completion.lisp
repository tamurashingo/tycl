(in-package :tycl.lsp)

;;; Completion - Code Completion

(defun get-completion-context (text line character)
  "Analyze context to determine what kind of completion to provide"
  (let* ((lines (split-string text #\Newline))
         (current-line (if (< line (length lines))
                          (nth line lines)
                          ""))
         (prefix (subseq current-line 0 (min character (length current-line)))))
    (cond
      ;; Type annotation context: [symbol :
      ((search "[" prefix :from-end t)
       :type)
      ;; Function call context: (symbol
      ((and (search "(" prefix :from-end t)
            (not (search ")" prefix :from-end t)))
       :function)
      ;; Default: symbol completion
      (t :symbol))))

(defun extract-prefix (text line character)
  "Extract the prefix to complete"
  (let* ((lines (split-string text #\Newline))
         (current-line (if (< line (length lines))
                          (nth line lines)
                          "")))
    (when (< character (length current-line))
      (let* ((start (or (position-if-not #'symbol-char-p current-line
                                        :end character
                                        :from-end t)
                       -1)))
        (when (< (1+ start) character)
          (string-upcase (subseq current-line (1+ start) character)))))))

(defun get-type-completions (prefix)
  "Get completion items for type keywords"
  (let ((types tycl::*valid-types*)
        (items '()))
    (dolist (type types)
      (let ((type-str (format nil "~(~A~)" type)))
        (when (or (null prefix)
                 (string= prefix "")
                 (and (>= (length type-str) (length prefix))
                      (string-equal prefix (subseq type-str 0 (length prefix)))))
          (push (make-completion-item type-str 25 type-str) items))))
    items))

(defun get-function-completions (prefix)
  "Get completion items for functions"
  (let ((symbols (get-all-symbols))
        (items '()))
    (dolist (symbol symbols)
      (when (eq (type-info-kind symbol) :function)
        (let ((name (type-info-name symbol)))
          (when (or (null prefix)
                   (string= prefix "")
                   (and (>= (length name) (length prefix))
                        (string-equal prefix (subseq name 0 (length prefix)))))
            (push (make-completion-item-with-detail
                   name 3
                   (format-function-detail symbol))
                  items)))))
    items))

(defun get-value-completions (prefix)
  "Get completion items for variables"
  (let ((symbols (get-all-symbols))
        (items '()))
    (dolist (symbol symbols)
      (when (eq (type-info-kind symbol) :value)
        (let ((name (type-info-name symbol)))
          (when (or (null prefix)
                   (string= prefix "")
                   (and (>= (length name) (length prefix))
                        (string-equal prefix (subseq name 0 (length prefix)))))
            (push (make-completion-item-with-detail
                   name 6
                   (format-type-spec (type-info-type-spec symbol)))
                  items)))))
    items))

(defun get-symbol-completions (prefix)
  "Get completion items for all symbols"
  (append (get-function-completions prefix)
          (get-value-completions prefix)))

(defun make-completion-item (label kind detail)
  "Create a completion item
  kind: 1=Text, 2=Method, 3=Function, 6=Variable, 7=Class, 25=Keyword"
  `((:label . ,label)
    (:kind . ,kind)
    (:detail . ,detail)))

(defun make-completion-item-with-detail (label kind detail)
  "Create a completion item with detail"
  `((:label . ,label)
    (:kind . ,kind)
    (:detail . ,detail)
    (:documentation . ((:kind . "markdown")
                      (:value . ,detail)))))

(defun format-function-detail (info)
  "Format function detail for completion"
  (let ((type-spec (type-info-type-spec info)))
    (if (and (consp type-spec)
            (eq (car type-spec) :function))
        (let ((params (second type-spec))
              (return-type (third type-spec)))
          (format nil "(~{~A~^ ~}) -> ~A"
                 (mapcar #'format-type-spec params)
                 (format-type-spec return-type)))
        "function")))

(defun get-completion-items (uri line character)
  "Get completion items for position in document"
  (let* ((text (gethash uri *open-documents*))
         (context (and text (get-completion-context text line character)))
         (prefix (and text (extract-prefix text line character))))
    (when text
      (case context
        (:type (get-type-completions prefix))
        (:function (get-function-completions prefix))
        (:symbol (get-symbol-completions prefix))
        (otherwise '())))))
