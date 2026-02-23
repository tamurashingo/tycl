# TyCL LSP Server Design

## 1. Overview

This is the design document for TyCL's standalone LSP server.

### Architecture

```
┌─────────────┐
│ Editor/IDE  │ (VS Code, Emacs, Vim, etc.)
└──────┬──────┘
       │ JSON-RPC (stdio/TCP)
       ↓
┌─────────────────────┐
│  TyCL LSP Server    │
│  (tycl-lsp.ros)     │
├─────────────────────┤
│ - Protocol Handler  │
│ - Type Info Cache   │
│ - File Watcher      │
│ - Diagnostics       │
└──────┬──────────────┘
       │
       ↓
┌─────────────────────┐
│ .tycl-types Files   │ (Type Information Database)
└─────────────────────┘
```

### Basic Principles

- **Standalone Execution**: Implemented as a Roswell script (`roswell/tycl-lsp.ros`)
- **LSP Compliant**: Conforms to Language Server Protocol 3.17
- **Communication**: JSON-RPC 2.0 via stdin/stdout
- **Type Information Source**: Read from `.tycl-types` files
- **Real-time Updates**: Reload type information on file changes

---

## 2. Implemented Features

### Phase 1: Basic Features (Required)

#### 2.1 Initialization and Termination

- `initialize` - Initialize connection with client
- `initialized` - Initialization complete notification
- `shutdown` - Server shutdown
- `exit` - Process termination

#### 2.2 Document Synchronization

- `textDocument/didOpen` - File open notification
- `textDocument/didChange` - File change notification
- `textDocument/didSave` - File save notification
- `textDocument/didClose` - File close notification

#### 2.3 Diagnostics

- Syntax error detection
- Type checking error detection
- Undefined symbol detection

### Phase 2: Completion and Information Display

#### 2.4 Code Completion

- `textDocument/completion` - Provide completion candidates
  - Function name completion
  - Variable name completion
  - Type keyword completion
  - Package name completion

#### 2.5 Hover Information

- `textDocument/hover` - Display type information when cursor hovers over symbol
  - Function signature display
  - Variable type display
  - Class/method information display

#### 2.6 Go to Definition

- `textDocument/definition` - Jump to symbol definition location

### Phase 3: Advanced Features

#### 2.7 Signature Help

- `textDocument/signatureHelp` - Display parameter information during function calls

#### 2.8 Find References

- `textDocument/references` - Search for symbol references

#### 2.9 Rename

- `textDocument/rename` - Batch rename symbols

#### 2.10 Document Symbols

- `textDocument/documentSymbol` - List of symbols in file

---

## 3. Technology Stack

### 3.1 Required Libraries

| Library | Purpose | Quicklisp |
|---------|---------|-----------|
| `cl-json` | JSON parsing/generation | ✓ |
| `usocket` | TCP communication (optional) | ✓ |
| `bordeaux-threads` | Multi-threaded processing | ✓ |
| `ironclad` | Hash calculation (for caching) | ✓ |

### 3.2 File Structure

```
roswell/
  tycl-lsp.ros        # LSP server entry point

src/lsp/
  packages.lisp       # Package definitions
  protocol.lisp       # JSON-RPC & LSP protocol processing
  handlers.lisp       # LSP method handlers
  completion.lisp     # Completion functionality
  hover.lisp          # Hover information
  diagnostics.lisp    # Diagnostics functionality
  document-sync.lisp  # Document synchronization
  type-query.lisp     # Type information queries
  cache.lisp          # Type information cache management
```

---

## 4. Data Flow

### 4.1 On Startup

```
1. Start tycl-lsp.ros
   ↓
2. Initialize stdio in JSON-RPC mode
   ↓
3. Receive initialize request
   ↓
4. Scan .tycl-types files in workspace
   ↓
5. Load type information into memory (build cache)
   ↓
6. Send initialized notification
```

### 4.2 When Editing Files

```
1. Receive textDocument/didChange notification
   ↓
2. Update document in memory
   ↓
3. Execute syntax check
   ↓
4. Send diagnostics via textDocument/publishDiagnostics
```

### 4.3 On Save

```
1. Receive textDocument/didSave notification
   ↓
2. Call TyCL transpiler
   ↓
3. Update .tycl-types file
   ↓
4. Reload type information cache
   ↓
5. Send diagnostics via textDocument/publishDiagnostics
```

### 4.4 On Completion Request

```
1. Receive textDocument/completion request
   ↓
2. Analyze context at cursor position
   ↓
3. Search for candidates from type information cache
   ↓
4. Return completion candidate list
```

---

## 5. Type Information Cache

### 5.1 Data Structure

```lisp
;; Global cache
(defvar *type-info-cache* (make-hash-table :test 'equal))

;; Key: Package name
;; Value: Hash table of symbol information within package
;;     Key: Symbol name
;;     Value: Type information (type-info structure)

;; Example:
;; *type-info-cache* = {
;;   "MY-PACKAGE" => {
;;     "ADD" => #<TYPE-INFO function (integer integer) -> integer>
;;     "*CONFIG*" => #<TYPE-INFO value hash-table<string, integer>>
;;   }
;; }
```

### 5.2 Cache Update Strategy

- **On Startup**: Load all `.tycl-types` files
- **On Save**: Reload `.tycl-types` for the corresponding file
- **Periodic Check**: Monitor file system changes (optional)

---

## 6. JSON-RPC Protocol

### 6.1 Message Format

LSP is based on JSON-RPC 2.0.

```
Content-Length: <byte count>\r\n
\r\n
{JSON-RPC message}
```

**Example:**

```
Content-Length: 95\r\n
\r\n
{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"processId":1234,"rootUri":"file:///path"}}
```

### 6.2 Request Processing

```lisp
(defun handle-request (request)
  "Dispatch LSP request to appropriate handler"
  (let* ((method (gethash "method" request))
         (params (gethash "params" request))
         (id (gethash "id" request)))
    (cond
      ((string= method "initialize")
       (handle-initialize params id))
      ((string= method "textDocument/completion")
       (handle-completion params id))
      ;; ... other methods
      (t
       (send-error id -32601 "Method not found")))))
```

---

## 7. Implementation Details

### 7.1 Protocol Layer

**File**: `src/lsp/protocol.lisp`

```lisp
(defun read-message (stream)
  "Read LSP message from stream"
  (let* ((headers (read-headers stream))
         (content-length (parse-content-length headers))
         (body (read-body stream content-length)))
    (json:decode-json-from-string body)))

(defun write-message (stream message)
  "Write LSP message to stream"
  (let* ((json (json:encode-json-to-string message))
         (bytes (babel:string-to-octets json :encoding :utf-8))
         (length (length bytes)))
    (format stream "Content-Length: ~D~C~C~C~C" length #\Return #\Newline #\Return #\Newline)
    (write-sequence bytes stream)
    (force-output stream)))
```

### 7.2 Type Information Cache

**File**: `src/lsp/cache.lisp`

```lisp
(defstruct type-info
  name          ; Symbol name
  kind          ; :function, :variable, :class, :method, etc.
  type          ; Type annotation
  signature     ; Function signature (for functions)
  docstring     ; Documentation string
  location)     ; Definition location (file, line, column)

(defun load-type-info-file (filepath)
  "Load type information from .tycl-types file"
  (with-open-file (stream filepath)
    (let ((data (read stream)))
      (parse-type-info data))))

(defun get-symbol-type-info (package-name symbol-name)
  "Retrieve type information for a symbol"
  (let ((package-cache (gethash package-name *type-info-cache*)))
    (when package-cache
      (gethash symbol-name package-cache))))
```

### 7.3 Completion Handler

**File**: `src/lsp/completion.lisp`

```lisp
(defun handle-completion (params id)
  "Handle textDocument/completion request"
  (let* ((uri (get-param params "textDocument" "uri"))
         (position (get-param params "position"))
         (line (gethash "line" position))
         (character (gethash "character" position))
         (context (analyze-context uri line character))
         (candidates (find-completion-candidates context)))
    (send-response id (make-completion-list candidates))))

(defun find-completion-candidates (context)
  "Find completion candidates based on context"
  (case (context-type context)
    (:function-name (find-function-names (context-prefix context)))
    (:variable-name (find-variable-names (context-prefix context)))
    (:type-keyword (find-type-keywords (context-prefix context)))
    (t nil)))
```

---

## 8. Editor Integration

### 8.1 VS Code

**Configuration**: `settings.json`

```json
{
  "tycl.lsp.executable": "ros",
  "tycl.lsp.args": ["run", "roswell/tycl-lsp.ros"],
  "files.associations": {
    "*.tycl": "commonlisp"
  }
}
```

### 8.2 Emacs (lsp-mode)

```elisp
(use-package lsp-mode
  :hook (tycl-mode . lsp)
  :config
  (lsp-register-client
   (make-lsp-client
    :new-connection (lsp-stdio-connection '("ros" "run" "roswell/tycl-lsp.ros"))
    :major-modes '(lisp-mode)
    :server-id 'tycl-lsp
    :activation-fn (lambda (filename &optional _)
                     (string-suffix-p ".tycl" filename)))))
```

### 8.3 Vim/Neovim (coc.nvim)

```json
{
  "languageserver": {
    "tycl": {
      "command": "ros",
      "args": ["run", "roswell/tycl-lsp.ros"],
      "filetypes": ["tycl", "lisp"],
      "rootPatterns": ["tycl.asd", ".git"]
    }
  }
}
```

---

## 9. Testing Strategy

### 9.1 Unit Tests

```lisp
;; test/lsp/protocol-test.lisp
(deftest test-json-rpc-parse
  (testing "Parse JSON-RPC request"
    (let ((msg "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\"}"))
      (ok (equal (parse-json-rpc msg)
                 '(:jsonrpc "2.0" :id 1 :method "initialize"))))))

;; test/lsp/completion-test.lisp
(deftest test-completion
  (testing "Function name completion"
    (with-fixture tycl-workspace
      (ok (member "my-add" (get-completion-items "my-a"))))))
```

### 9.2 Integration Tests

```bash
# test/lsp/integration/
# Actual communication tests using LSP client
test-initialize.sh
test-completion.sh
test-hover.sh
```

### 9.3 Editor Tests

- Verify actual behavior in each editor
- Screenshots and demo videos

---

## 10. Performance Considerations

### 10.1 Caching Strategy

- **Memory Cache**: All type information held in memory
- **Differential Updates**: Only reload affected packages on file changes
- **Lazy Loading**: For large projects, prioritize loading necessary packages

### 10.2 Response Time Goals

| Operation | Target Response Time |
|-----------|---------------------|
| Completion | < 50ms |
| Hover | < 30ms |
| Diagnostics | < 200ms |
| Go to Definition | < 100ms |

### 10.3 Optimization Techniques

- Pre-indexing of type information
- Priority caching of frequently used symbols
- Asynchronous diagnostics processing
- Incremental parsing

---

## 11. Security

### 11.1 Sandbox

- LSP server is read-only for files
- Transpiler execution only on explicit save
- No arbitrary code execution

### 11.2 Resource Limits

- Memory usage upper limit
- Processing limits for large files
- Timeout settings

---

## 12. Error Handling

### 12.1 LSP Error Codes

| Code | Meaning |
|------|---------|
| -32700 | Parse error |
| -32600 | Invalid Request |
| -32601 | Method not found |
| -32602 | Invalid params |
| -32603 | Internal error |

### 12.2 Diagnostic Severity

| Severity | Usage |
|----------|-------|
| Error (1) | Syntax errors, type errors |
| Warning (2) | Type mismatches, discouraged usage |
| Information (3) | Type inference results |
| Hint (4) | Optimization suggestions |

---

## 13. Documentation

### 13.1 User Documentation

- `LSP-SETUP.md` - Setup instructions for each editor
- `LSP-FEATURES.md` - Feature list and usage
- `LSP-TROUBLESHOOTING.md` - Troubleshooting

### 13.2 Developer Documentation

- `LSP-PROTOCOL.md` - Protocol details
- `LSP-ARCHITECTURE.md` - Architecture explanation
- `LSP-CONTRIBUTING.md` - Contribution guide

---

## 14. Implementation Roadmap

### Milestone 1: Proof of Concept (2 weeks)

- Minimal LSP server implementation
- initialize/shutdown
- hover (basic type information display)

### Milestone 2: MVP (4 weeks)

- Completion functionality
- Diagnostics functionality
- VS Code extension

### Milestone 3: Feature Complete (8 weeks)

- All LSP features implemented
- Multiple editor support
- Performance optimization

### Milestone 4: Production Ready (12 weeks)

- Bug fixes
- Documentation refinement
- Test coverage 80%+

---

## 15. References

- [LSP Specification](https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/)
- [JSON-RPC 2.0 Specification](https://www.jsonrpc.org/specification)
- [cl-lsp](https://github.com/cxxxr/cl-lsp) - Reference Common Lisp LSP implementation
- [lem-lsp-mode](https://github.com/lem-project/lem) - Lem editor's LSP implementation

---

## 16. Implementation Status

### ✅ Complete (Phase 1)

- **Basic LSP Server Framework**
  - Added `lsp` command to `roswell/tycl.ros`
  - Implemented server main loop in `src/lsp/server.lisp`
  - Package definitions in `src/lsp/packages.lisp`

- **JSON-RPC Protocol Processing**
  - Implemented message parsing/generation in `src/lsp/protocol.lisp`
  - Content-Length header processing
  - JSON-RPC 2.0 compliant request/response processing

- **Basic Handlers**
  - Implemented the following in `src/lsp/handlers.lisp`:
    - `initialize` - Client connection initialization
    - `initialized` - Initialization complete notification
    - `shutdown` - Server shutdown
    - `exit` - Process termination
    - `textDocument/didOpen` - File open notification
    - `textDocument/didChange` - File change notification
    - `textDocument/didSave` - File save notification
    - `textDocument/didClose` - File close notification

- **Type Information Cache**
  - Implemented type information loading/management in `src/lsp/cache.lisp`
  - Load type information from `.tycl-types` files
  - Cache management per package/symbol

### 🚧 Next Steps (Phase 2)

- **Diagnostics** (`textDocument/publishDiagnostics`)
  - Syntax error detection
  - Type checking error detection
  - Undefined symbol detection

- **Hover Feature** (`textDocument/hover`)
  - Function signature display
  - Variable type display

- **Completion Feature** (`textDocument/completion`)
  - Function name completion
  - Variable name completion
  - Type keyword completion

---

**Last Updated**: 2026-02-22  
**Status**: Phase 1 Complete, Phase 2 In Progress
