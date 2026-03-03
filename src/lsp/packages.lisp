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
   #:schedule-diagnostics
   #:process-pending-diagnostics
   #:nearest-deadline
   #:compute-timeout-ms
   
   ;; Hover
   #:get-hover-info
   
   ;; Completion
   #:get-completion-items

   ;; Protocol (timeout)
   #:read-json-rpc-message-with-timeout

   ;; ASD parser
   #:find-asd-files
   #:load-asd-file
   #:find-system-for-file
   #:resolve-output-path
   #:load-and-cache-asd-files
   #:transpile-tycl-file
   #:transpile-all-in-asd
   #:check-all-in-asd
   #:*cached-asd-files*
   #:*cached-asd-systems*))

(in-package :tycl.lsp)

(defvar *debug-mode* nil
  "Enable debug logging when T")

(defvar *shutdown-requested* nil
  "Flag indicating shutdown was requested")

(defvar *pending-diagnostics* (make-hash-table :test 'equal)
  "Hash table mapping URI to deadline (internal-real-time) for pending diagnostics")

(defvar *diagnostics-debounce-ms* 500
  "Debounce delay in milliseconds before computing diagnostics after a change.
   0 means immediate (no debounce). Can be overridden via initializationOptions.")
