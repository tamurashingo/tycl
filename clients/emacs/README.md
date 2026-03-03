# TyCL Emacs Client

Emacs major mode for TyCL (Typed Common Lisp) with LSP support.

## Installation

### Prerequisites

- Emacs 26.1 or later
- `lsp-mode` package
- TyCL LSP server (`ros install tamurashingo/tycl`)

### Using straight.el or package.el

1. Copy `tycl-mode.el` to your Emacs load path, or add this directory to `load-path`:

```elisp
(add-to-list 'load-path "/path/to/tycl/clients/emacs")
(require 'tycl-mode)
```

2. Install dependencies:

```elisp
(use-package lsp-mode
  :ensure t
  :hook (tycl-mode . lsp-deferred)
  :commands (lsp lsp-deferred))
```

### Configuration

#### Basic Setup

```elisp
;; In your init.el or .emacs
(require 'tycl-mode)

;; TyCL files will automatically use tycl-mode
;; (already configured via auto-mode-alist)
```

#### Settings Reference

All settings can be customized via `M-x customize-group RET tycl RET` or by setting variables in your init file.

##### LSP Server

| Variable | Default | Description |
|----------|---------|-------------|
| `tycl-lsp-server-command` | `'("tycl" "lsp")` | Command to start TyCL LSP server |
| `tycl-lsp-server-root-path` | `nil` | Path to TyCL source directory (for development only). When set, uses `roswell/tycl.ros` under this directory instead of the installed `tycl` command |

##### Diagnostics

| Variable | Default | Description |
|----------|---------|-------------|
| `tycl-diagnostics-debounce-ms` | `500` | Delay in milliseconds before computing diagnostics after a change. Set to `0` for immediate diagnostics |

##### Swank Server

| Variable | Default | Description |
|----------|---------|-------------|
| `tycl-swank-enabled` | `nil` | If non-nil, start a Swank server alongside the LSP server |
| `tycl-swank-port` | `4005` | Port number for the Swank server |

#### Examples

##### Development with local TyCL source

Set `tycl-lsp-server-root-path` to the **TyCL project root directory** (the parent of the directory containing `roswell/tycl.ros`):

```
/home/user/projects/tycl/          <-- set this path
├── roswell/
│   └── tycl.ros
├── src/
└── ...
```

```elisp
(setq tycl-lsp-server-root-path "/home/user/projects/tycl")
```

This runs `ros /home/user/projects/tycl/roswell/tycl.ros lsp` instead of the installed `tycl` command.

##### Immediate diagnostics (no debounce)

```elisp
(setq tycl-diagnostics-debounce-ms 0)
```

##### Enable Swank server for SLIME REPL integration

```elisp
(setq tycl-swank-enabled t)
(setq tycl-swank-port 4005)  ; default
```

When enabled, the LSP server process also starts a Swank server. Connect from SLIME with `M-x slime-connect RET localhost RET 4005`.

##### With use-package

```elisp
(use-package tycl-mode
  :load-path "/path/to/tycl/clients/emacs"
  :mode "\\.tycl\\'"
  :hook (tycl-mode . lsp-deferred)
  :custom
  (tycl-lsp-server-root-path "/path/to/tycl")
  (tycl-diagnostics-debounce-ms 500)
  (tycl-swank-enabled t)
  (tycl-swank-port 4005))
```

## Features

### Syntax Highlighting

- Type annotations: `[x :integer]`
- Type keywords: `:integer`, `:string`, etc.
- Union types: `(:integer :string)`
- Generics: `(:list (:integer))`

### LSP Features (when connected)

- **Hover**: Show type information on hover
- **Completion**: Auto-complete symbols and types
- **Diagnostics**: Real-time error checking
- **Go to Definition**: Jump to symbol definition
- **References**: Find all references to a symbol

## Usage

### Opening a TyCL File

Files with `.tycl` extension automatically activate `tycl-mode`:

```lisp
;; example.tycl
(defun [add :integer] ([x :integer] [y :integer])
  (+ x y))
```

### Starting LSP

When you open a TyCL file, LSP should start automatically if `lsp-mode` is configured with `:hook (tycl-mode . lsp-deferred)`.

Alternatively, manually start LSP with:

```
M-x lsp
```

### Checking LSP Status

```
M-x lsp-describe-session
```

### LSP Commands

| Command | Key | Description |
|---------|-----|-------------|
| `lsp-find-definition` | `M-.` | Jump to definition |
| `lsp-find-references` | `M-?` | Find references |
| `lsp-rename` | `C-c r` | Rename symbol |
| `lsp-ui-doc-glance` | `C-c d` | Show documentation |

## Troubleshooting

### LSP Server Not Starting

1. Check if `tycl` is in your PATH:
   ```bash
   which tycl
   ```

2. Test the LSP server manually:
   ```bash
   tycl lsp
   ```

3. Check Emacs `*lsp-log*` buffer for errors:
   ```
   M-x switch-to-buffer *lsp-log*
   ```

### Custom Server Command

If the default command doesn't work, customize it:

```elisp
(setq tycl-lsp-server-command '("tycl" "lsp"))
;; Or for development with local source (alternative to tycl-lsp-server-root-path):
(setq tycl-lsp-server-command '("ros" "/full/path/to/roswell/tycl.ros" "lsp"))
```

### Syntax Highlighting Not Working

Ensure `tycl-mode` is active:

```
M-x describe-mode
```

If not, manually activate it:

```
M-x tycl-mode
```

## Development

### Testing the Mode

1. Open a `.tycl` file
2. Check that `tycl-mode` is active (appears in mode line)
3. Verify syntax highlighting for type annotations
4. Test LSP features (hover, completion, etc.)

### Debugging LSP Connection

Enable verbose logging:

```elisp
(setq lsp-log-io t)
```

Then check `*lsp-log*` buffer for JSON-RPC messages.

## Contributing

Contributions welcome! Please submit issues or pull requests to the main TyCL repository.

## License

MIT License - see LICENSE file in the main TyCL repository.
