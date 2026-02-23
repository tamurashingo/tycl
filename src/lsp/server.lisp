(in-package :tycl.lsp)

;;; Main Server Loop

(defun dispatch-message (method params id stream)
  "Dispatch LSP message to appropriate handler"
  (handler-case
      (cond
        ;; Lifecycle
        ((string= method "initialize")
         (handle-initialize params id stream))
        ((string= method "initialized")
         (handle-initialized params stream))
        ((string= method "shutdown")
         (handle-shutdown id stream))
        ((string= method "exit")
         (handle-exit))
        
        ;; Document sync
        ((string= method "textDocument/didOpen")
         (handle-did-open params stream))
        ((string= method "textDocument/didChange")
         (handle-did-change params stream))
        ((string= method "textDocument/didSave")
         (handle-did-save params stream))
        ((string= method "textDocument/didClose")
         (handle-did-close params stream))
        
        ;; Language features
        ((string= method "textDocument/hover")
         (handle-hover params id stream))
        ((string= method "textDocument/completion")
         (handle-completion params id stream))
        ((string= method "completionItem/resolve")
         (handle-completion-resolve params id stream))
        ((string= method "textDocument/definition")
         (handle-definition params id stream))
        ((string= method "textDocument/documentSymbol")
         (handle-document-symbol params id stream))
        
        ;; Unknown method
        (t
         (when *debug-mode*
           (format *error-output* "~%Unknown method: ~A~%" method))
         (when id
           (send-error id -32601 "Method not found" stream))))
    (error (e)
      (when *debug-mode*
        (format *error-output* "~%Error handling ~A: ~A~%" method e))
      (when id
        (send-error id -32603 (format nil "Internal error: ~A" e) stream)))))

(defun start-server (&key (input *standard-input*) (output *standard-output*) debug)
  "Start the LSP server main loop"
  (setf *debug-mode* debug)
  (setf *shutdown-requested* nil)
  
  (when *debug-mode*
    (format *error-output* "~%TyCL LSP Server starting...~%"))
  
  (loop
    (let ((message (read-json-rpc-message input)))
      (unless message
        (return))
      
      (multiple-value-bind (jsonrpc id method params)
          (parse-message message)
        (declare (ignore jsonrpc))
        
        (when *debug-mode*
          (format *error-output* "~%Method: ~A, ID: ~A~%" method id))
        
        (dispatch-message method params id output)
        
        ;; Exit if shutdown was handled
        (when (and (string= method "exit"))
          (return))))))
