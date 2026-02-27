(defpackage :tycl.lsp
  (:use :cl)
  (:export
   ;; Main entry point
   #:start-server
   
   ;; Protocol
   #:parse-message
   #:send-message
   #:send-response
   #:send-error
   #:send-notification
   
   ;; Handlers
   #:handle-initialize
   #:handle-initialized
   #:handle-shutdown
   #:handle-exit
   #:handle-did-open
   #:handle-did-change
   #:handle-did-save
   #:handle-did-close
   #:handle-hover
   #:handle-completion
   #:handle-definition
   #:handle-document-symbol
   
   ;; Type info cache
   #:load-type-info
   #:query-type-info
   #:clear-cache
   
   ;; Diagnostics
   #:publish-diagnostics
   
   ;; Hover
   #:get-hover-info
   
   ;; Completion
   #:get-completion-items

   ;; ASD parser
   #:find-asd-files
   #:load-asd-file
   #:find-system-for-file
   #:resolve-output-path
   #:load-and-cache-asd-files
   #:transpile-tycl-file
   #:transpile-all-in-asd
   #:*cached-asd-files*
   #:*cached-asd-systems*))

(in-package :tycl.lsp)

(defvar *debug-mode* nil
  "Enable debug logging when T")

(defvar *shutdown-requested* nil
  "Flag indicating shutdown was requested")
