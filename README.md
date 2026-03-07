# TyCL - Typed Common Lisp

**Pronunciation**: /ˈtɪkəl/ (sounds like "tickle")

TyCL (Typed Common Lisp) is a type system extension that brings gradual typing and modern development experience to Common Lisp.

## Project Goals

- **Enhanced Developer Experience**: Provide code completion, static analysis, and documentation through LSP (Language Server Protocol) based on type information
- **Full Compatibility with Existing CL**: Code with type annotations can be executed directly in standard Common Lisp implementations
- **Optional Typing**: Works with or without types, allowing gradual type adoption

## Features

### Type Annotation Syntax

Intuitive type annotations using `[]` (brackets):

```lisp
;; Function definition
(defun [add :integer] ([x :integer] [y :integer])
  (+ x y))

;; Variable binding
(let (([name :string] (get-name))
      (age 30))  ; Type inference
  (format t "~A is ~A years old" name age))

;; Local functions
(flet (([square :integer] ([n :integer])
         (* n n)))
  (square 5))
```

### Union Types

Accept multiple types:

```lisp
(defun [process :void] ([value (:integer :string)])
  (typecase value
    (integer (handle-number value))
    (string (handle-string value))))
```

### Generics (Collection Types)

Data structures with type parameters:

```lisp
;; Specify element type for lists (Java: List<Integer>)
(defun [sum-list :integer] ([nums (:list (:integer))])
  (reduce #'+ nums :initial-value 0))

;; Hash tables (Java: Map<String, String>)
(defun [lookup (:string :null)] 
       ([table (:hash-table (:string) (:string))]
        [key :string])
  (gethash key table))

;; Nested generics (Java: List<List<String>>)
(defun [matrix (:list (:list (:string)))] ()
  ...)
```

### Type Variables and Polymorphism

Define generic functions with type variables using `<T>` notation:

```lisp
;; Single type variable
(defun [identity <T> T] ([x T])
  x)
;; => (defun identity (x) x)

;; Compound return type using type variable
(defun [wrap <T> (:list (T))] ([x T])
  (list x))
;; => (defun wrap (x) (list x))

;; Multiple type variables
(defun [swap-pair <A B> (:cons B A)] ([p (:cons A B)])
  (cons (cdr p) (car p)))
;; => (defun swap-pair (p) (cons (cdr p) (car p)))

;; Type variable in parameters
(defun [first-or-default <T> T] ([lst (:list T)] [default T])
  (if lst (first lst) default))
;; => (defun first-or-default (lst default) (if lst (first lst) default))
```

The `<...>` notation is only active inside `[...]` brackets. Outside brackets, `<` and `>` remain normal symbols, so `(< a b)` works as expected.

### Type Aliases

Reusable type definitions with `deftype-tycl`:

```lisp
;; Simple alias
(deftype-tycl userid :integer)
(deftype-tycl nullable-num (:integer :null))

;; Parametric type aliases
(deftype-tycl (result T) (:list (T)))
(deftype-tycl (pair A B) (:list (A B)))

;; Usage
(defun [get-user :string] ([id userid])
  (fetch-user-from-db id))

(defun [get-range (result :integer)] ([start :integer] [end :integer])
  (loop for i from start to end collect i))

(defun [make-pair (pair :integer :string)] ([n :integer] [label :string])
  (list n label))
```

Type aliases are resolved during transpilation and do not appear in the generated `.lisp` output.

### Type Casting (Type Assertion)

The bracket notation `[expr type]` can also be used on arbitrary expressions to assert a type. This works like TypeScript's `as` operator — it tells the type checker to treat the expression as the specified type without affecting the generated code.

```lisp
(defun [foo :integer] () 3)
(defun [hello :void] ([msg :string])
  (format t "msg: ~A~%" msg))

;; (hello (foo)) — type error: :integer is not compatible with :string
;; Use a type cast to override:
(hello [(foo) :string])
;; => (hello (foo))
```

Any expression can be cast:

```lisp
;; Cast a function call result
(process [(get-value) :string])

;; Cast an arithmetic expression
(display [(+ 1 2) :string])
```

**Note**: Type casts are unchecked — they override the type checker without runtime validation. Use them when you know the types are compatible at runtime but the type checker cannot infer this.

## Available Types

### Basic Types

- **Numbers**: `:integer`, `:float`, `:double-float`, `:rational`, `:number`, etc.
- **Strings**: `:string`, `:character`, `:simple-string`
- **Sequences**: `:list`, `:vector`, `:array`, `:cons`
- **Logic**: `:boolean`, `:symbol`, `:keyword`
- **Control**: `:void` (no return value), `:null`, `:t` (any type)
- **Others**: `:function`, `:hash-table`, `:stream`, `:pathname`

## Usage

### Command Line Interface

TyCL provides a command-line tool for transpiling and type checking:

```bash
# Transpile a .tycl file to .lisp
tycl transpile src/example.tycl

# Transpile with custom output path
tycl transpile src/example.tycl build/example.lisp

# Check type annotations
tycl check src/example.tycl

# Show help
tycl help
```

**Installation:**

```bash
# Install with roswell (recommended)
ros install tamurashingo/tycl
```

After installation, the `tycl` command is available directly in your PATH.

### Loading TyCL Files

```lisp
;; Load and transpile a .tycl file
(tycl:load-tycl "src/example.tycl")

;; With options
(tycl:load-tycl "src/example.tycl" 
                :output-dir "build"        ; Output directory
                :if-exists :overwrite      ; Overwrite existing files
                :compile t)                ; Compile before loading

;; Or use shorthand
(tycl:compile-and-load-tycl "src/example.tycl" :if-exists :overwrite)
```

### Transpiling Files

```lisp
;; Transpile a single file
(tycl:transpile-file "src/example.tycl" "src/example.lisp")

;; Transpile a string
(tycl:transpile-string 
  "(defun [add :integer] ([x :integer] [y :integer]) (+ x y))")
```

### Type Checking

```lisp
;; Check types in a file
(tycl:check-file "src/example.tycl")
;; => T (no errors) or NIL (errors found)

;; Check types in a string
(tycl:check-string "(defun [add :integer] ([x :integer]) x)")
;; => T
```

### ASDF Integration

TyCL provides an ASDF extension that allows `.tycl` files to be used directly in `defsystem` definitions. `asdf:load-system` handles the full transpile → compile → load pipeline automatically.

```lisp
(defsystem my-app
  :class tycl/asdf:tycl-system
  :defsystem-depends-on (#:tycl)
  :tycl-output-dir "build/"
  :components
  ((:module "src"
    :serial t
    :components
    ((:file "config")            ; plain .lisp — copied to output dir
     (:tycl-file "math")        ; .tycl — transpiled to .lisp
     (:tycl-file "main")))))
```

#### System Options

| Option | Default | Description |
|--------|---------|-------------|
| `:tycl-output-dir` | `nil` | Output directory for transpiled/copied files. Relative to system root. When `nil`, files are generated alongside sources. |
| `:tycl-extract-types` | `t` | Extract type information during transpilation |
| `:tycl-save-types` | `t` | Save type information to `tycl-types.tmp` |

#### Forward Declaration Stub

When ASDF reads a `.asd` file, the Lisp reader must resolve `tycl/asdf:tycl-system` **before** `:defsystem-depends-on` loads TyCL. Add this stub before your `defsystem` form:

```lisp
(unless (find-package :tycl/asdf)
  (defpackage #:tycl/asdf
    (:export #:tycl-system #:tycl-file)))
```

See [docs/asdf.md](docs/asdf.md) for the full design document and a [sample project](sample/) for a working example.

### Type Information Storage

When using `load-tycl` or `tycl transpile`, TyCL collects and stores type information during transpilation:
- Which package
- Which function/variable/class
- What type it has

This enables:
1. Post-transpilation type consistency checks
2. LSP server type information queries
3. Cross-package type dependency tracking
4. Type-based documentation generation

Type information is saved in a project-level `tycl-types.tmp` file. When using `tycl transpile-all`, the file is generated next to the `.asd` file. When using `tycl transpile` for a single file, it is generated in the current directory. The file contains multiple S-expressions (one per package) and supports merge-on-write to accumulate type information across transpilations.

### Custom Macro Support

TyCL supports custom macros through a hook mechanism. This allows extracting type information from project-specific macro definitions.

The `:type-extractor` function receives the entire form and returns a list of plists, each describing one type definition. Each plist must contain `:kind` (one of `:value`, `:function`, `:class`, `:method`), `:symbol`, and the relevant type fields.

```lisp
;; Register a type extractor for a custom API macro
;; (define-api get-user :params ((id :integer)) :return :string)
(tycl:register-type-extractor 'define-api
  :type-extractor
    (lambda (form)
      (let ((name (second form))
            (body (cddr form)))
        (list
         `(:kind :function
           :symbol ,name
           :params ,(mapcar (lambda (p)
                              (list :name (symbol-name (first p))
                                    :type (second p)))
                            (getf body :params))
           :return ,(getf body :return))))))
```

A hook can also return multiple type definitions at once (e.g., a class, its constructor, and a predicate):

```lisp
;; Register a type extractor for a model macro
;; (defmodel person :slots ((name :string) (age :integer)))
(tycl:register-type-extractor 'defmodel
  :type-extractor
    (lambda (form)
      (let ((name (second form))
            (slots (getf (cddr form) :slots)))
        (list
         `(:kind :class
           :symbol ,name
           :slots ,(mapcar (lambda (s)
                             (list :name (symbol-name (first s))
                                   :type (second s)))
                           slots))
         `(:kind :function
           :symbol ,(intern (format nil "MAKE-~A" name))
           :params ,(mapcar (lambda (s)
                              (list :name (symbol-name (first s))
                                    :type (second s)))
                            slots)
           :return ,name)))))
```

Hooks can be loaded automatically from a `tycl-hooks.lisp` file placed in your project root. The file is loaded when `load-tycl` or `transpile-file` is called:

```lisp
;;;; tycl-hooks.lisp

(in-package #:tycl)

(register-type-extractor 'my-framework:define-entity
  :type-extractor
    (lambda (form)
      (list `(:kind :class
              :symbol ,(second form)
              :slots ,(extract-entity-slots form)))))
```

### LSP Integration

TyCL provides a Language Server Protocol implementation for modern editor integration.

#### Starting LSP Server

```bash
tycl lsp
```

#### Editor Clients

##### VS Code

A full-featured VS Code extension is available in `clients/vscode/`:

```bash
cd clients/vscode
npm install
npm run compile
npm run package
code --install-extension tycl-0.1.0.vsix
```

Development configuration example (`.vscode/settings.json`):

```json
{
  "tycl.lsp.serverPath": "/path/to/tycl-project-root"
}
```

See [clients/vscode/README.md](clients/vscode/README.md) for details.

##### Emacs

Install `tycl-mode` from `clients/emacs/`:

```elisp
(add-to-list 'load-path "/path/to/tycl/clients/emacs")
(require 'tycl-mode)

;; With lsp-mode
(use-package lsp-mode
  :hook (tycl-mode . lsp-deferred))

;; Optional: for development, specify TyCL project root
(setq tycl-lsp-server-root-path "/path/to/tycl-project-root")
```

See [clients/emacs/README.md](clients/emacs/README.md) for details.

##### Vim/Neovim

Configure with coc.nvim or other LSP clients:

```json
{
  "languageserver": {
    "tycl": {
      "command": "tycl",
      "args": ["lsp"],
      "filetypes": ["tycl", "lisp"],
      "rootPatterns": ["tycl.asd", ".git"]
    }
  }
}
```

#### LSP Features

- **Hover**: Show type information for symbols
- **Completion**: Context-aware code completion
- **Diagnostics**: Real-time type checking and error detection
- **Go to Definition**: Navigate to symbol definitions
- **Find References**: Locate all uses of a symbol
- **Document Symbols**: Outline view of file structure

#### Startup Behavior

When the LSP server starts, it performs the following initialization:

1. **`.asd` file discovery**: Scans the workspace root for `.asd` files
2. **Full transpilation**: If `.asd` files with `tycl-system` definitions are found, all `.tycl` files in those systems are transpiled to generate `tycl-types.tmp`. This runs unconditionally regardless of whether `tycl-types.tmp` already exists, ensuring type information is always up-to-date.
3. **Type information loading**: Loads `tycl-types.tmp` files from the workspace to populate the type cache

This ensures that LSP features (hover, completion, diagnostics) have complete type information available from the first interaction.

#### Diagnostics Debounce

By default, diagnostics are debounced with a 500ms delay to avoid unnecessary CPU load during continuous typing. The debounce delay can be configured via the editor client:

- **VS Code**: `tycl.diagnostics.debounceMs` setting (0-5000ms, default: 500)
- **Other clients**: Send `diagnosticDebounceMs` in `initializationOptions`

Setting the value to `0` disables debouncing and computes diagnostics immediately on every change. File save always triggers diagnostics immediately regardless of the debounce setting.

See [docs/lsp-server.md](docs/lsp-server.md) for implementation details.

## Development

### Project Structure

```
tycl/
├── src/              # Core transpiler and type checker
│   └── asdf.lisp    # ASDF extension (tycl-system, tycl-file)
├── test/             # Test suite
├── roswell/          # CLI tools
├── clients/          # Editor clients
│   ├── emacs/       # Emacs tycl-mode
│   └── vscode/      # VS Code extension
├── sample/           # Sample project using ASDF integration
└── docs/             # Documentation
    ├── design.md         # Design specification
    ├── asdf.md           # ASDF extension design
    └── lsp-server.md     # LSP server design
```

### Running Tests

```bash
# Run all tests
make test

# Unit tests only
make test.unit

# CLI integration tests
make test.cli
```

## License

MIT
