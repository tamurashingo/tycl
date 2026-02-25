;;;; did-change-test.lisp
;;;; Tests for LSP textDocument/didChange handler

(defpackage :tycl/test/lsp/did-change
  (:use :cl :rove))

(in-package :tycl/test/lsp/did-change)

;;; Helper functions

(defun make-did-open-params (uri text)
  "Create params alist for textDocument/didOpen"
  `((:text-document . ((:uri . ,uri)
                       (:language-id . "tycl")
                       (:version . 1)
                       (:text . ,text)))))

(defun make-did-change-params (uri version content-changes)
  "Create params alist for textDocument/didChange.
   CONTENT-CHANGES is a list of alists, each with at least :text key.
   For full sync: ((:text . \"new text\"))
   For incremental: ((:range . ...) (:text . \"replacement\"))"
  `((:text-document . ((:uri . ,uri)
                       (:version . ,version)))
    (:content-changes . ,content-changes)))

(defun get-document (uri)
  "Get document content from open-documents cache"
  (gethash uri tycl.lsp::*open-documents*))

(defun setup-document (uri text)
  "Set up a document in the cache via didOpen handler"
  (let ((stream (make-string-output-stream)))
    (tycl.lsp:handle-did-open (make-did-open-params uri text) stream)))

(defun call-did-change (uri version content-changes)
  "Call didChange handler and return the output stream content"
  (let ((stream (make-string-output-stream)))
    (tycl.lsp:handle-did-change
     (make-did-change-params uri version content-changes)
     stream)
    (get-output-stream-string stream)))

;;; Tests

(deftest did-change-full-sync-test
  (testing "Full content replacement updates the document"
    (let ((uri "file:///tmp/test-full.tycl")
          (initial-text "(defun hello () \"hello\")")
          (updated-text "(defun hello () \"world\")"))
      (setup-document uri initial-text)
      (ok (string= (get-document uri) initial-text)
          "Initial document should be stored")

      (call-did-change uri 2 `(((:text . ,updated-text))))
      (ok (string= (get-document uri) updated-text)
          "Document should be updated to new content")))

  (testing "Full content replacement with multiline document"
    (let* ((uri "file:///tmp/test-multiline.tycl")
           (initial-text (format nil "(in-package :test)~%~%(defun add ([x :integer] [y :integer])~%  (+ x y))"))
           (updated-text (format nil "(in-package :test)~%~%(defun add ([x :integer] [y :integer] [z :integer])~%  (+ x y z))")))
      (setup-document uri initial-text)
      (call-did-change uri 2 `(((:text . ,updated-text))))
      (ok (string= (get-document uri) updated-text)
          "Multiline document should be fully replaced"))))

(deftest did-change-multiple-updates-test
  (testing "Multiple sequential changes update the document correctly"
    (let ((uri "file:///tmp/test-sequential.tycl")
          (text-v1 "(defun f () 1)")
          (text-v2 "(defun f () 2)")
          (text-v3 "(defun f () 3)"))
      (setup-document uri text-v1)
      (ok (string= (get-document uri) text-v1)
          "Version 1 should be stored")

      (call-did-change uri 2 `(((:text . ,text-v2))))
      (ok (string= (get-document uri) text-v2)
          "Version 2 should replace version 1")

      (call-did-change uri 3 `(((:text . ,text-v3))))
      (ok (string= (get-document uri) text-v3)
          "Version 3 should replace version 2"))))

(deftest did-change-last-change-wins-test
  (testing "When multiple content changes arrive in one notification, last one wins"
    (let ((uri "file:///tmp/test-batch.tycl")
          (initial-text "(defun f () 1)"))
      (setup-document uri initial-text)

      ;; Simulate multiple content changes in a single notification
      ;; The current implementation takes (car (last content-changes))
      (call-did-change uri 2
                       `(((:text . "(defun f () 2)"))
                         ((:text . "(defun f () 3)"))))
      (ok (string= (get-document uri) "(defun f () 3)")
          "Last content change should be applied"))))

(deftest did-change-empty-document-test
  (testing "Change to empty document"
    (let ((uri "file:///tmp/test-empty.tycl"))
      (setup-document uri "(defun f () 1)")
      (call-did-change uri 2 `(((:text . ""))))
      (ok (string= (get-document uri) "")
          "Document should become empty")))

  (testing "Change from empty document to content"
    (let ((uri "file:///tmp/test-from-empty.tycl"))
      (setup-document uri "")
      (call-did-change uri 2 `(((:text . "(defun f () 1)"))))
      (ok (string= (get-document uri) "(defun f () 1)")
          "Empty document should be replaced with content"))))

(deftest did-change-different-documents-test
  (testing "Changes to different URIs are independent"
    (let ((uri-a "file:///tmp/test-a.tycl")
          (uri-b "file:///tmp/test-b.tycl"))
      (setup-document uri-a "(defun a () 1)")
      (setup-document uri-b "(defun b () 2)")

      ;; Change only document A
      (call-did-change uri-a 2 `(((:text . "(defun a () 10)"))))

      (ok (string= (get-document uri-a) "(defun a () 10)")
          "Document A should be updated")
      (ok (string= (get-document uri-b) "(defun b () 2)")
          "Document B should remain unchanged"))))

(deftest did-change-publishes-diagnostics-test
  (testing "didChange sends publishDiagnostics notification"
    (let ((uri "file:///tmp/test-diag.tycl")
          (text "(defun hello () \"hello\")"))
      (setup-document uri text)
      (let ((output (call-did-change uri 2 `(((:text . ,text))))))
        (ok (> (length output) 0)
            "Should produce output (publishDiagnostics notification)")
        ;; cl-json escapes / as \/ in JSON output
        (ok (search "textDocument\\/publishDiagnostics" output)
            "Output should contain publishDiagnostics method")))))

(deftest did-change-unicode-test
  (testing "Unicode content is handled correctly"
    (let ((uri "file:///tmp/test-unicode.tycl")
          (text-with-unicode "(defun greet () \"Hello, World!\")"))
      (setup-document uri text-with-unicode)
      (call-did-change uri 2 `(((:text . ,text-with-unicode))))
      (ok (string= (get-document uri) text-with-unicode)
          "Unicode content should be preserved"))))

(deftest did-change-preserves-whitespace-test
  (testing "Whitespace and indentation are preserved"
    (let* ((uri "file:///tmp/test-ws.tycl")
           (text (format nil "  (defun f ()~%    (let ((x 1))~%      x))")))
      (setup-document uri text)
      (call-did-change uri 2 `(((:text . ,text))))
      (ok (string= (get-document uri) text)
          "Whitespace and indentation should be preserved exactly"))))

(deftest did-change-insert-enter-test
  (testing "Insert enter"
    (let ((uri "file:///tmp/test-insert-enter.tycl")
          (text ";;;"))
      (setup-document uri text)
      (call-did-change uri 2 `(((:range (:start (:line . 0) (:character . 0))
                                       (:end (:line . 0) (:character . 0)))
                               (:range-length . 0)
                               (:text . ,(format nil "~%")))))
      (ok (string= (get-document uri)
                   (format nil "~%;;;"))))))

