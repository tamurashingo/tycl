;;; tycl-mode.el --- Major mode for TyCL (Typed Common Lisp) -*- lexical-binding: t; -*-

;; Copyright (C) 2026

;; Author: TyCL Contributors
;; Version: 0.1.0
;; Package-Requires: ((emacs "26.1") (lsp-mode "8.0.0"))
;; Keywords: languages lisp
;; URL: https://github.com/tamurashingo/tycl

;;; Commentary:

;; This package provides a major mode for editing TyCL (Typed Common Lisp) files
;; with LSP support.
;;
;; Usage:
;;   (require 'tycl-mode)
;;   (add-to-list 'auto-mode-alist '("\\.tycl\\'" . tycl-mode))

;;; Code:

(require 'lisp-mode)
(require 'lsp-mode nil t)

(defgroup tycl nil
  "Major mode for TyCL (Typed Common Lisp)."
  :group 'languages
  :prefix "tycl-")

(defcustom tycl-lsp-server-command '("tycl" "lsp")
  "Command to start TyCL LSP server."
  :type '(repeat string)
  :group 'tycl)

(defcustom tycl-lsp-server-root-path nil
  "Path to TyCL source directory for development.
When set, uses roswell/tycl.ros under this directory instead of the installed tycl command.
If nil, uses `tycl-lsp-server-command' as-is."
  :type '(choice (const :tag "Use system PATH" nil)
                 (directory :tag "TyCL installation directory"))
  :group 'tycl)

(defcustom tycl-diagnostics-debounce-ms 500
  "Delay in milliseconds before computing diagnostics after a change.
0 means immediate (no debounce)."
  :type 'integer
  :group 'tycl)

(defcustom tycl-swank-enabled nil
  "If non-nil, start a Swank server alongside the LSP server."
  :type 'boolean
  :group 'tycl)

(defcustom tycl-swank-port 4005
  "Port number for the Swank server.
Only used when `tycl-swank-enabled' is non-nil."
  :type 'integer
  :group 'tycl)

(defvar tycl-mode-syntax-table
  (let ((table (make-syntax-table lisp-mode-syntax-table)))
    ;; Type annotation brackets
    (modify-syntax-entry ?\[ "(]" table)
    (modify-syntax-entry ?\] ")[" table)
    table)
  "Syntax table for `tycl-mode'.")

(defvar tycl-font-lock-keywords
  (append
   lisp-font-lock-keywords-2
   '(;; Type annotations [symbol :type]
     ("\\[\\([^[:space:]]+\\)[[:space:]]+\\(:[^]]+\\)\\]"
      (1 font-lock-variable-name-face)
      (2 font-lock-type-face))
     ;; Standalone type keywords
     ("\\(:[a-z-]+\\)" 1 font-lock-type-face)))
  "Font lock keywords for `tycl-mode'.")

;;;###autoload
(define-derived-mode tycl-mode lisp-mode "TyCL"
  "Major mode for editing TyCL (Typed Common Lisp) files.

TyCL extends Common Lisp with optional type annotations using
the [symbol :type] syntax.

\\{tycl-mode-map}"
  :syntax-table tycl-mode-syntax-table
  (setq-local font-lock-defaults '(tycl-font-lock-keywords))
  (setq-local comment-start ";")
  (setq-local comment-end "")

  ;; LSP setup
  (when (featurep 'lsp-mode)
    (tycl-lsp-setup)))

(defun tycl--build-server-command ()
  "Build the LSP server command list, including Swank arguments if enabled."
  (let ((cmd (if tycl-lsp-server-root-path
                 (list "ros"
                       (expand-file-name "roswell/tycl.ros"
                                         tycl-lsp-server-root-path)
                       "lsp")
               (copy-sequence tycl-lsp-server-command))))
    (when tycl-swank-enabled
      (setq cmd (append cmd (list "--swank" (number-to-string tycl-swank-port)))))
    cmd))

(defun tycl-lsp-setup ()
  "Set up LSP for TyCL mode."
  (when (fboundp 'lsp-register-client)
    (lsp-register-client
     (make-lsp-client
      :new-connection (lsp-stdio-connection #'tycl--build-server-command)
      :major-modes '(tycl-mode)
      :server-id 'tycl-lsp
      :priority 1
      :initialization-options
      (lambda ()
        `(:diagnosticDebounceMs ,tycl-diagnostics-debounce-ms))
      :activation-fn (lambda (filename &optional _)
                       (string-match-p "\\.tycl\\'" filename))))))

;;;###autoload
(add-to-list 'auto-mode-alist '("\\.tycl\\'" . tycl-mode))

(provide 'tycl-mode)

;;; tycl-mode.el ends here
