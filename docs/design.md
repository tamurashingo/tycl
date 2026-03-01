# TyCL (Typed Common Lisp) Design Document

## 1. Overview

TyCL is a transpiler for adding type annotations to Common Lisp. Like TypeScript, it converts TyCL source code (`.tycl`) into standard Common Lisp source code (`.lisp`).

### Architecture

```
example.tycl  →  [Transpile]  →  example.lisp  →  [Compile]  →  example.fasl
```

### Basic Principles

- **TyCL Files (`.tycl`)**: Lisp code with type annotations
- **Transpiler**: Simply converts `[symbol type]` to `symbol`
- **Generated Files (`.lisp`)**: 100% pure Common Lisp
- **Runtime Dependencies**: None (TyCL package not required)
- **TyCL Package**: Only contains transpiler implementation

---

## 2. Type Annotation Syntax

**Basic Format**: `[symbol type]`

### 2.1 Function Definition (`defun`)

```lisp
;; Input (example.tycl)
(defun [add :integer] ([x :integer] [y :integer])
  (+ x y))

;; Output (example.lisp)
(defun add (x y)
  (+ x y))
```

### 2.2 Local Variables (`let`)

```lisp
;; Input
(let (([x :integer] 10)
      (y 20)
      ([name :string] (get-name)))
  (+ x y))

;; Output
(let ((x 10)
      (y 20)
      (name (get-name)))
  (+ x y))
```

### 2.3 Local Functions (`flet`, `labels`)

```lisp
;; Input
(flet (([helper :integer] ([n :integer])
         (* n 2)))
  (helper 5))

;; Output
(flet ((helper (n)
         (* n 2)))
  (helper 5))
```

---

## 3. Type System

### 3.1 Basic Types

List of basic types available in TyCL.

#### 3.1.1 Numeric Types

| Type Keyword | Description | Common Lisp Type |
|--------------|-------------|------------------|
| `:integer` | Integer | `integer` |
| `:fixnum` | Fixed-length integer | `fixnum` |
| `:bignum` | Arbitrary-precision integer | `bignum` |
| `:float` | Floating-point number | `float` |
| `:single-float` | Single-precision float | `single-float` |
| `:double-float` | Double-precision float | `double-float` |
| `:rational` | Rational number | `rational` |
| `:ratio` | Ratio (fraction) | `ratio` |
| `:real` | Real number | `real` |
| `:number` | General numeric | `number` |
| `:complex` | Complex number | `complex` |

#### 3.1.2 Character and String Types

| Type Keyword | Description | Common Lisp Type |
|--------------|-------------|------------------|
| `:character` | Character | `character` |
| `:base-char` | Base character | `base-char` |
| `:standard-char` | Standard character | `standard-char` |
| `:string` | String | `string` |
| `:base-string` | Base string | `base-string` |
| `:simple-string` | Simple string | `simple-string` |

#### 3.1.3 Sequence Types

| Type Keyword | Description | Common Lisp Type |
|--------------|-------------|------------------|
| `:list` | List | `list` |
| `:cons` | Cons cell | `cons` |
| `:null` | Empty list/nil | `null` |
| `:vector` | Vector | `vector` |
| `:simple-vector` | Simple vector | `simple-vector` |
| `:bit-vector` | Bit vector | `bit-vector` |
| `:array` | Array | `array` |
| `:simple-array` | Simple array | `simple-array` |
| `:sequence` | General sequence | `sequence` |

#### 3.1.4 Boolean and Control Types

| Type Keyword | Description | Common Lisp Type |
|--------------|-------------|------------------|
| `:boolean` | Boolean (t or nil) | `boolean` |
| `:symbol` | Symbol | `symbol` |
| `:keyword` | Keyword symbol | `keyword` |
| `:void` | No return value | `(values)` |
| `:nil` | nil type | `nil` |

#### 3.1.5 Function and Other Types

| Type Keyword | Description | Common Lisp Type |
|--------------|-------------|------------------|
| `:function` | Function | `function` |
| `:compiled-function` | Compiled function | `compiled-function` |
| `:hash-table` | Hash table | `hash-table` |
| `:stream` | Stream | `stream` |
| `:pathname` | Pathname | `pathname` |
| `:package` | Package | `package` |
| `:readtable` | Readtable | `readtable` |
| `:random-state` | Random state | `random-state` |

#### 3.1.6 Special Types

| Type Keyword | Description | Usage Example |
|--------------|-------------|---------------|
| `:t` | Any type (Top type) | When type information is unknown |
| `:any` | Any type (alias for `:t`) | To disable type checking |

### 3.2 Union Types

Multiple types listed within parentheses:

```lisp
;; Input
(defun [process :void] ([value (:integer :string)])
  (typecase value
    (integer (handle-number value))
    (string (handle-string value))))

;; Output
(defun process (value)
  (typecase value
    (integer (handle-number value))
    (string (handle-string value))))
```

### 3.3 Generics (Parameterized Types)

Type parameters are nested in parentheses:

```lisp
;; Input
(defun [sum-list :integer] ([nums (:list (:integer))])
  (reduce #'+ nums :initial-value 0))

;; Output
(defun sum-list (nums)
  (reduce #'+ nums :initial-value 0))
```

**Syntax Examples:**
- `(:list (:integer))` - List<Integer>
- `(:hash-table (:string) (:integer))` - Map<String, Integer>
- `(:list (:integer :string))` - List<Integer | String>

### 3.4 Type Variables and Polymorphism (Planned)

**⚠️ Not Implemented - Planned for Future**

Use type variables to define generic functions that work with multiple types.

```lisp
;; T is a type variable (any type)
(defun [identity <T> T] ([x T])
  x)

;; Multiple type variables
(defun [pair <A B> (:cons A B)] ([first A] [second B])
  (cons first second))

;; Type variables with constraints
(defun [compare <T :number> :symbol] ([a T] [b T])
  (cond ((< a b) :less)
        ((> a b) :greater)
        (t :equal)))
```

### 3.5 Custom Types

Define custom types using `deftype-tycl`:

```lisp
;; Input
(deftype-tycl userid :integer)

(defun [get-user :string] ([id userid])
  (fetch-user-from-db id))

;; Output
(defun get-user (id)
  (fetch-user-from-db id))
```

**Syntax:**
- `(deftype-tycl name type)` - Define a type alias
- `(deftype-tycl name (base-type &rest params))` - Define with parameters

---

## 4. Transpiler Implementation

### 4.1 Core Functions

#### `transpile-file`

Transpiles a `.tycl` file to a `.lisp` file.

```lisp
(transpile-file "example.tycl" "example.lisp")
```

#### `transpile-string`

Transpiles TyCL code from a string.

```lisp
(transpile-string "(defun [add :integer] ([x :integer] [y :integer]) (+ x y))")
```

#### `transpile-form`

Transpiles a single TyCL form (S-expression).

```lisp
(transpile-form '(defun [add :integer] ([x :integer] [y :integer]) (+ x y)))
;; => (defun add (x y) (+ x y))
```

### 4.2 Processing Flow

1. **Read**: Parse `.tycl` file as S-expressions
2. **Transform**: Strip type annotations (`[symbol type]` → `symbol`)
3. **Write**: Output transformed code to `.lisp` file

### 4.3 Type Annotation Transformation Rules

| Input Pattern | Output |
|---------------|--------|
| `[symbol type]` | `symbol` |
| `([sym1 type1] init1)` | `(sym1 init1)` |
| `([sym1 type1])` | `(sym1)` |
| `(defun [fname type] ...)` | `(defun fname ...)` |

---

## 5. ASDF Integration

### 5.1 `:tycl-file` Component

Custom ASDF component for `.tycl` files:

```lisp
(defsystem "my-system"
  :defsystem-depends-on ("tycl")
  :components ((:tycl-file "example")))
```

### 5.2 Automatic Transpilation

- ASDF automatically transpiles `.tycl` → `.lisp` during builds
- Generated `.lisp` files are treated as build artifacts
- Compilation is skipped if `.tycl` is unchanged

### 5.3 Usage Example

```lisp
;; my-system.asd
(defsystem "my-system"
  :defsystem-depends-on ("tycl")
  :components ((:tycl-file "src/core")
               (:tycl-file "src/utils")))

;; Build with ASDF
(asdf:load-system "my-system")
```

---

## 6. Development Roadmap

### Phase 1: Basic Transpiler ✅ **Complete**
- [x] Core transpiler
  - [x] `defun` type annotations
  - [x] `let` type annotations
  - [x] `flet`, `labels` type annotations
  - [x] `lambda` type annotations
  - [x] Union types
  - [x] Generics (parameterized types)
- [x] File I/O
  - [x] Read `.tycl` files
  - [x] Write `.lisp` files
  - [x] Source location preservation
- [x] CLI interface
  - [x] `tycl transpile <input> <output>`
  - [x] Roswell script (`ros install tycl`)
  - [x] `tycl load <file>` - Transpile and load directly into REPL

### Phase 2: ASDF Integration ✅ **Complete**
- [x] Custom ASDF component (`:tycl-file`)
- [x] Auto-transpilation during build
- [x] Dependency tracking
- [x] Build caching
- [x] Error handling

### Phase 3: Basic Type System ✅ **Complete**
- [x] Type keyword parsing
  - [x] Numeric types (`:integer`, `:float`, etc.)
  - [x] String types (`:string`, `:character`, etc.)
  - [x] Sequence types (`:list`, `:vector`, `:array`, etc.)
  - [x] Boolean/control types (`:boolean`, `:void`, `:nil`)
  - [x] Function types (`:function`, `:compiled-function`)
  - [x] Other types (`:hash-table`, `:stream`, `:pathname`, etc.)
- [x] Union types (`:integer | :string` → `(:integer :string)`)
- [x] Generics (`List<Integer>` → `(:list (:integer))`)

### Phase 4: Custom Type System ✅ **Complete**
- [x] `deftype-tycl` - Define custom types
  - [x] Type aliases (e.g., `userid` → `:integer`)
  - [x] Parameterized types
- [x] Type registry
  - [x] Global type registration
  - [x] Type lookup/validation
  - [x] Type expansion
- [x] Error handling
  - [x] Duplicate type definition detection
  - [x] Undefined type reference warnings

### Phase 5: Type Information Export ✅ **Complete**

**Purpose:**
Extract and store type information from `.tycl` files for later use.

Type information includes:
- Which package
- Which function/variable
- What type it has

This enables type consistency checking and LSP completion/type hints.

Type information is saved in a project-level `tycl-types.tmp` file (S-expression format containing multiple packages) and `.tycl-types.json` file (JSON format), which can be reused on next load.

**Intended Uses:**
1. LSP server type information (completion, hover, diagnostics)
2. Post-transpilation type consistency checking
3. Tracking type dependencies between packages
4. Type-based documentation generation

---

### Phase 6: LSP Server 🚧 **Partially Complete**

**Phase 1: Basic Features ✅ Complete**
- [x] LSP server entry point (`roswell/tycl.ros lsp`)
- [x] JSON-RPC protocol handling (`src/lsp/protocol.lisp`)
  - [x] Content-Length header processing
  - [x] JSON-RPC 2.0 message parsing/generation
- [x] Basic handlers (`src/lsp/handlers.lisp`)
  - [x] `initialize` - Client connection initialization
  - [x] `initialized` - Initialization complete notification
  - [x] `shutdown` - Server shutdown
  - [x] `exit` - Process exit
  - [x] `textDocument/didOpen` - File open notification
  - [x] `textDocument/didChange` - File change notification
  - [x] `textDocument/didSave` - File save notification
  - [x] `textDocument/didClose` - File close notification
- [x] Type information cache (`src/lsp/cache.lisp`)
  - [x] Load type information from `tycl-types.tmp` file
  - [x] Cache management per package/symbol
- [x] Server main loop (`src/lsp/server.lisp`)
- [x] Package definitions (`src/lsp/packages.lisp`)

**Phase 2: Diagnostics, Completion, Hover ✅ Complete**
- [x] Diagnostics (`src/lsp/diagnostics.lisp`)
  - [x] `textDocument/publishDiagnostics` - Error notifications
  - [x] Syntax error detection
  - [x] Type checking error detection
  - [x] Undefined symbol detection
- [x] Hover feature (`src/lsp/hover.lisp`)
  - [x] `textDocument/hover` - Hover information on symbols
  - [x] Function signature display
  - [x] Variable type display
  - [x] Class/method information display
- [x] Completion feature (`src/lsp/completion.lisp`)
  - [x] `textDocument/completion` - Completion candidates
  - [x] Function name completion
  - [x] Variable name completion
  - [x] Type keyword completion

**Phase 3: Advanced Features (Partially Implemented)**
- [x] Go to definition (`textDocument/definition`) - Stub: handler registered, capability advertised, returns null
- [ ] Signature help (`textDocument/signatureHelp`)
- [ ] Find references (`textDocument/references`)
- [ ] Rename (`textDocument/rename`)
- [x] Document symbols (`textDocument/documentSymbol`) - Stub: handler registered, capability advertised, returns empty list

**Phase 4: Editor Integration ✅ Complete**
- [x] VS Code extension (`clients/vscode/`)
  - [x] Extension manifest (`package.json`)
  - [x] TypeScript extension code
  - [x] TyCL syntax highlighting (TextMate grammar)
  - [x] Language configuration (bracket matching, comment definitions)
  - [x] README (setup instructions)
- [x] Emacs integration (`clients/emacs/`)
  - [x] `tycl-mode.el` - Major mode with LSP support
  - [x] Syntax highlighting
  - [x] `lsp-mode` integration settings
  - [x] README (configuration examples)
- [x] Vim/Neovim configuration examples (documented in lsp-server.md)

**Dependencies:**
- `cl-json` - JSON parsing/generation
- `babel` - Byte array and string conversion (portable)

See **lsp-server.md** for details.

---

### Phase 7: Advanced Type Features (Future Plans)

- [ ] Type aliases (`deftype-alias`)
  - [ ] Simple type aliases (e.g., `UserID` → `:integer`)
  - [ ] Generic type aliases (e.g., `Result<T, E>`)
- [ ] Type variables and polymorphism
  - [ ] Type variable syntax (`<T>`, `<A B>`)
  - [ ] Type constraints (e.g., `<T :number>`)
  - [ ] Generic function definitions
- [ ] Extended generics
  - [ ] More complex nested generics
  - [ ] Custom types combined with generics
- [x] Struct/class slot type definitions - Partially: `defclass` slot type extraction implemented (`src/type-extractor.lisp`), `defstruct` not supported
- [ ] Type narrowing (type refinement in conditional branches)
- [x] Optional type checking during transpilation - Partially: basic infrastructure exists (`src/type-checker.lisp`) with `check-form`, `check-string`, `check-file`, `type-compatible-p`, `infer-type`; not integrated into transpiler flow (`*enable-type-checking*` flag unused)

---

## 7. Advantages

1. **Simple**: Just remove type annotations
2. **Compatible**: Generated code is 100% standard Common Lisp
3. **No Runtime Overhead**: Processing only during transpilation
4. **Works with Existing Tools**: ASDF, Quicklisp, etc. work as-is
5. **Gradual Migration**: `.tycl` and `.lisp` can coexist
6. **Easy Debugging**: Generated code can be directly inspected
7. **REPL-Ready**: Easy loading with `load-tycl`

---

## 8. Sample Code

### Input (example.tycl)

```lisp
(defpackage #:my-app
  (:use #:cl))

(in-package #:my-app)

(defun [add :integer] ([x :integer] [y :integer])
  "Add two integers"
  (+ x y))

(defun [greet :string] ([name :string])
  "Greet a person"
  (format nil "Hello, ~A!" name))

(let (([result :integer] (add 3 4))
      ([message :string] (greet "Alice")))
  (format t "~A Result: ~A~%" message result))
```

### Output (example.lisp)

```lisp
;;;; Generated by TyCL transpiler
;;;; DO NOT EDIT

(defpackage #:my-app
  (:use #:cl))

(in-package #:my-app)

(defun add (x y)
  "Add two integers"
  (+ x y))

(defun greet (name)
  "Greet a person"
  (format nil "Hello, ~A!" name))

(let ((result (add 3 4))
      (message (greet "Alice")))
  (format t "~A Result: ~A~%" message result))
```

---

## 9. Design Decisions

### 9.1 Why the Transpiler Approach?

Initially, we tried a read macro approach to process types at compile time, but changed to a transpiler approach for the following reasons:

1. **Tool Compatibility**: Compatibility issues with existing CL tools (ASDF, Rove, etc.)
2. **Compile-Time Complexity**: Complex handling of `eval-when`
3. **Debugging Difficulty**: Hard to track errors during macro expansion
4. **Explicitness**: Better to be able to inspect transpiled code

### 9.2 Why Minimize the TyCL Package?

- **Avoid Runtime Dependencies**: Generated code is plain CL
- **Simplicity**: Focus only on the transpiler
- **Future Extensibility**: Add necessary features when implementing LSP

---

## 10. Future Outlook

### Short-Term (Next Milestone)
- **Custom Type Registration**: Support for user-defined types
- **Type Aliases**: Reusable type definitions (`deftype-alias`)
- **Type Variables**: Polymorphic function definitions (`<T>`)

### Mid-Term
- **Type Inference**: Basic type inference support
- **Type Checking**: Optional type checking during transpilation
- **LSP Server**: Completion/diagnostics using type information
- **IDE Integration**: Plugins for Emacs, Vim, VS Code, etc.

### Long-Term
- **Type Narrowing**: Type refinement in conditional branches
- **Dependent Types**: Types dependent on values (e.g., array length)
- **Effect System**: Side effect tracking
- **Refinement Types**: Precise types using predicates (e.g., `(integer :positive)`)
- **Documentation Generation**: Auto-generate API documentation from type information
