(in-package :tycl.lsp)

;;; JSON-RPC Message Handling

(defun read-headers (stream)
  "Read HTTP-style headers until blank line"
  (loop for line = (read-line stream nil nil)
        while (and line (not (string= line (string #\Return))))
        collect (string-trim (list #\Return #\Newline) line)))

(defun parse-content-length (headers)
  "Extract Content-Length from headers"
  (loop for header in headers
        when (and (>= (length header) 15)
                  (string-equal (subseq header 0 15) "Content-Length:"))
        do (return (parse-integer (string-trim " " (subseq header 15))))))

(defun read-json-rpc-message (stream)
  "Read a complete JSON-RPC message from stream"
  (handler-case
      (let* ((headers (read-headers stream))
             (content-length (parse-content-length headers)))
        (when *debug-mode*
          (format *error-output* "~%Headers received: ~A~%" headers))
        (let ((content-length (parse-content-length headers)))
          (when *debug-mode*
            (format *error-output* "~%Content-Length: ~A~%" content-length))
          (when content-length
            (let ((buffer (make-string content-length)))
              (read-sequence buffer stream)
              (when *debug-mode*
                (format *error-output* "~%<<< ~A~%" buffer))
              (cl-json:decode-json-from-string buffer)))))
    (end-of-file ()
      (when *debug-mode*
        (format *error-output* "~%EOF reached~%"))
      nil)
    (error (e)
      (when *debug-mode*
        (format *error-output* "~%Error reading message: ~A~%" e))
      nil)))

(defun read-json-rpc-message-with-timeout (stream timeout-ms)
  "Read a JSON-RPC message with an optional timeout.
   If TIMEOUT-MS is NIL, block indefinitely (calls read-json-rpc-message).
   Otherwise, poll with listen + sleep at 10ms intervals.
   Returns the message alist, NIL on EOF, or :timeout if the deadline expires."
  (if (null timeout-ms)
      (read-json-rpc-message stream)
      (let ((deadline (+ (get-internal-real-time)
                         (* timeout-ms (/ internal-time-units-per-second 1000)))))
        (loop
          (when (listen stream)
            (return (read-json-rpc-message stream)))
          (when (>= (get-internal-real-time) deadline)
            (return :timeout))
          (sleep 0.01)))))

(defun write-json-rpc-message (message stream)
  "Write a JSON-RPC message to stream"
  (let* ((json (cl-json:encode-json-to-string message))
         (content-length (length (babel:string-to-octets json :encoding :utf-8))))
    (when *debug-mode*
      (format *error-output* "~%>>> ~A~%" json))
    (format stream "Content-Length: ~D~C~C~C~C~A"
            content-length
            #\Return #\Newline
            #\Return #\Newline
            json)
    (finish-output stream)))

(defun parse-message (alist)
  "Parse JSON-RPC message from alist"
  (let ((jsonrpc (cdr (assoc :jsonrpc alist)))
        (id (cdr (assoc :id alist)))
        (method (cdr (assoc :method alist)))
        (params (cdr (assoc :params alist))))
    (values jsonrpc id method params)))

(defun send-response (id result stream)
  "Send a JSON-RPC response"
  (write-json-rpc-message
   `((:jsonrpc . "2.0")
     (:id . ,id)
     (:result . ,result))
   stream))

(defun send-error (id code message stream)
  "Send a JSON-RPC error response"
  (write-json-rpc-message
   `((:jsonrpc . "2.0")
     (:id . ,id)
     (:error . ((:code . ,code)
                (:message . ,message))))
   stream))

(defun send-notification (method params stream)
  "Send a JSON-RPC notification"
  (write-json-rpc-message
   `((:jsonrpc . "2.0")
     (:method . ,method)
     (:params . ,params))
   stream))
