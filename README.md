# TyCL - Typed Common Lisp

**Pronunciation**: /ˈtɪkəl/ (sounds like "tickle")

TyCL (Typed Common Lisp) is a type system extension that brings gradual typing and modern development experience to Common Lisp.

- **Enhanced Developer Experience**: Provide code completion, static analysis, and documentation through LSP (Language Server Protocol) based on type information
- **Full Compatibility with Existing CL**: Code with type annotations can be executed directly in standard Common Lisp implementations
- **Optional Typing**: Works with or without types, allowing gradual type adoption

## Installation

```bash
# Install with roswell
ros install tamurashingo/tycl
```

After installation, the `tycl` command is available directly in your PATH.

## Commands

### tycl transpile

Transpile a `.tycl` file to `.lisp`, stripping type annotations and generating standard Common Lisp code.

```bash
tycl transpile <input.tycl> [<output.lisp>]
```

If the output path is omitted, it uses the same name with a `.lisp` extension.

```bash
# Transpile a .tycl file to .lisp
tycl transpile src/example.tycl

# Transpile with custom output path
tycl transpile src/example.tycl build/example.lisp
```

### tycl transpile-all

Transpile all `.tycl` files defined in a `.asd` file. This scans all `tycl-file` components across all `tycl-system` definitions in the given `.asd` file, transpiles each one, and saves project-level type information to `tycl-types.d.lisp` next to the `.asd` file.

```bash
tycl transpile-all <file.asd>
```

### tycl check

Type check a single `.tycl` file without transpiling. Returns exit code 0 if all types are valid, exit code 1 if errors are found.

```bash
tycl check <input.tycl>
```

### tycl check-all

Type check all `.tycl` files defined in a `.asd` file. Pre-loads `tycl-types.d.lisp` before checking so that dependency types are available.

```bash
tycl check-all <file.asd>
```

### tycl install

Download type declaration files for external libraries from the [tycl-declarations](https://github.com/tamurashingo/tycl-declarations) repository. Downloaded files are saved to `tycl-declarations/` in the current directory, where `check-all` and `transpile-all` automatically load them.

```bash
tycl install <package-name> [version]
```

If version is omitted, the latest version is determined from the package's `meta.sexp` in the repository. If no `meta.sexp` exists, the unversioned file is downloaded as a fallback.

```bash
# Install Common Lisp standard library declarations (latest)
tycl install common-lisp

# Install a specific version
tycl install cl-ppcre 0.2.0
```

To use a custom declarations repository, set the `TYCL_DECLARATIONS_URL` environment variable:

```bash
TYCL_DECLARATIONS_URL=https://raw.githubusercontent.com/yourname/your-declarations/main \
  tycl install my-library
```

### tycl install-from

Download type declarations for all dependencies listed in a `.asd` file. Reads `:depends-on` from all `defsystem` forms and installs declarations for each dependency.

```bash
tycl install-from <file.asd>
```

Version constraints using ASDF's `(:version "pkg" "ver")` syntax are respected. Dependencies without version constraints use the latest version.

```bash
tycl install-from sample-project.asd
```

### tycl lsp

Start the Language Server Protocol server. See the [LSP](#lsp) section for details.

```bash
tycl lsp
```

### tycl help

Show usage information for all commands.

```bash
tycl help
```

## Writing TyCL Code

### Type Annotations

TyCL uses `[]` (brackets) for type annotations:

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

### Lambda List Keywords

TyCL supports `&optional`, `&key`, and `&rest` parameters with type annotations. The type checker validates argument counts and types accordingly.

#### &optional

Optional parameters can be omitted by the caller. Default values are supported.

```lisp
(defun [greet :string] ([name :string]
                        &optional ([greeting :string] "Hello") [suffix :string])
  (let ((base (concatenate 'string greeting ", " name "!")))
    (if suffix
        (concatenate 'string base " " suffix)
        base)))

(greet "Alice")                      ; OK — greeting defaults to "Hello", suffix is nil
(greet "Alice" "Hi")                 ; OK
(greet "Alice" "Hey" "How are you?") ; OK
(greet "Alice" 42)                   ; Type error — expected :string, got :integer
```

#### &key

Keyword arguments can be passed in any order. Unknown keywords and type mismatches are detected.

```lisp
(defun [format-name :string] ([first-name :string] [last-name :string]
                               &key ([separator :string] " ") ([order :keyword] :western))
  ...)

(format-name "John" "Doe")                    ; OK
(format-name "John" "Doe" :separator ", ")     ; OK
(format-name "John" "Doe" :order :eastern)     ; OK
(format-name "John" "Doe" :unknown "x")        ; Error — unknown keyword
```

#### &rest

Rest parameters collect all remaining arguments into a list. The type annotation specifies the **element type** — inside the function body, the parameter is treated as `(:list (:element-type))`.

```lisp
(defun [concat-all :string] ([separator :string] &rest [strings :string])
  ;; strings has type (:list (:string)) inside the body
  (format nil (concatenate 'string "~{~A~^" separator "~}") strings))

(concat-all ", " "a" "b" "c")  ; OK — each rest arg is checked as :string
(concat-all ", " "a" 42)       ; Type error — 42 is not :string
```

`&optional`, `&key`, and `&rest` can be combined:

```lisp
(defun [f :t] ([x :integer] &optional [y :string] &key [verbose :boolean]) ...)
(defun [g :t] ([x :integer] &optional [y :string] &rest [args :t]) ...)
```

### Types

#### Basic Types

- **Numbers**: `:integer`, `:float`, `:double-float`, `:rational`, `:number`, etc.
- **Strings**: `:string`, `:character`, `:simple-string`
- **Sequences**: `:list`, `:vector`, `:array`, `:cons`
- **Logic**: `:boolean`, `:symbol`, `:keyword`
- **Control**: `:void` (no return value), `:null`, `:t` (any type)
- **Multiple values**: `:values` (see [Multiple Values](#multiple-values))
- **Others**: `:function`, `:hash-table`, `:stream`, `:pathname`

#### Union Types

Accept multiple types:

```lisp
;; integer or string
(defun [process :void] ([value (:integer :string)])
  (typecase value
    (integer (handle-number value))
    (string (handle-string value))))

;; nullable value
(defun [find-name (:string :null)] ([id :integer])
  (gethash id *name-table*))

;; union with generic types (see Generics section below)
(defun [parse-items ((:list (:string)) :null)] ([input :string])
  (when (valid-p input)
    (split-string input)))
```

#### Multiple Values

Functions that return multiple values use `:values`:

```lisp
;; Return quotient and remainder
(defun [div-mod (:values :integer :integer)] ([n :integer] [d :integer])
  (floor n d))

;; Return value and success flag
(defun [safe-parse (:values :number :boolean)] ([s :string])
  (handler-case
      (values (parse-integer s) t)
    (error () (values 0 nil))))
```

When a function declared with `(:values :integer :string)` is called in a context that expects a single value (e.g., `:integer`), the type checker treats the first value as the effective return type. This matches Common Lisp's behavior where `multiple-value-bind` captures all values but ordinary binding receives only the first.

```lisp
;; (:values :number :boolean) is compatible with :number
(defun [parse-or-zero :number] ([s :string])
  (safe-parse s))  ; second value (boolean) is discarded
```

### Custom Type Definitions (deftype-tycl)

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

### Generics

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

Define generic functions with type variables using `{E}` notation:

```lisp
;; Single type variable
(defun [identity {E} E] ([x E])
  x)
;; => (defun identity (x) x)

;; Compound return type using type variable
(defun [wrap {E} (:list (E))] ([x E])
  (list x))
;; => (defun wrap (x) (list x))

;; Multiple type variables
(defun [swap-pair {A B} (:cons B A)] ([p (:cons A B)])
  (cons (cdr p) (car p)))
;; => (defun swap-pair (p) (cons (cdr p) (car p)))

;; Type variable in parameters
(defun [first-or-default {E} E] ([lst (:list E)] [default E])
  (if lst (first lst) default))
;; => (defun first-or-default (lst default) (if lst (first lst) default))
```

The `{...}` notation is only active inside `[...]` brackets. Outside brackets, `{` and `}` remain normal characters.

### Class Inheritance and Subtype Polymorphism

TyCL supports subtype polymorphism through class inheritance. When a class inherits from another, the subclass is accepted wherever the parent type is expected:

```lisp
(defclass animal () ((name :type :string)))
(defclass dog (animal) ((breed :type :string)))

;; dog is accepted where animal is expected
(defun [greet :string] ([a animal])
  (slot-value a 'name))

(defun [greet-dog :string] ([d dog])
  (greet d))  ; OK — dog is a subtype of animal
```

Multi-level inheritance is also supported:

```lisp
(defclass a () ((x :type :integer)))
(defclass b (a) ((y :type :string)))
(defclass c (b) ((z :type :float)))

(defun [process :t] ([obj a]) obj)
(defun [use-c :t] ([obj c]) (process obj))  ; OK — c inherits from b, which inherits from a
```

Subtype checking is directional: a parent class cannot be used where a child type is expected, and unrelated classes are not compatible with each other.

### Accessor Type Inference

When a `defclass` slot has `:accessor` or `:reader`, TyCL automatically infers the accessor function's type from the slot type annotation. No separate function declaration is needed.

```lisp
(defclass person ()
  (([name :string] :initarg :name :accessor person-name)
   ([age :integer] :initarg :age :reader person-age)))

;; person-name is automatically typed as (person) -> :string
;; person-age  is automatically typed as (person) -> :integer

(defun [greeting :string] ([p person])
  (person-name p))  ; OK — return type is :string

(defun [bad :integer] ([p person])
  (person-name p))  ; Type error — :string is not compatible with :integer
```

If the same accessor name appears on multiple classes, the parameter and return types are widened to `:t`:

```lisp
(defclass book ()    (([label :string] :accessor get-label)))
(defclass product () (([label :keyword] :accessor get-label)))

;; get-label is typed as (:t) -> :t because it spans multiple classes
```

### Type Casting

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

## ASDF Integration

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

### System Options

| Option | Default | Description |
|--------|---------|-------------|
| `:tycl-output-dir` | `nil` | Output directory for transpiled/copied files. Relative to system root. When `nil`, files are generated alongside sources. |
| `:tycl-extract-types` | `t` | Extract type information during transpilation |
| `:tycl-save-types` | `t` | Save type information to `tycl-types.d.lisp` |

### Forward Declaration Stub

When ASDF reads a `.asd` file, the Lisp reader must resolve `tycl/asdf:tycl-system` **before** `:defsystem-depends-on` loads TyCL. Add this stub before your `defsystem` form:

```lisp
(unless (find-package :tycl/asdf)
  (defpackage #:tycl/asdf
    (:export #:tycl-system #:tycl-file)))
```

See [docs/asdf.md](docs/asdf.md) for the full design document and a [sample project](sample/) for a working example.

### Referencing Types from Other TyCL Projects

When a project depends on another TyCL project, type information from the dependency is automatically available.

During transpilation (`asdf:load-system` or `tycl transpile-all`), TyCL automatically loads `tycl-types.d.lisp` from all `tycl-system` dependencies before processing the current project. This means types defined in the dependency (functions, classes, variables) are available for type checking without any additional configuration.

To use this, specify the dependency in `:depends-on`:

```lisp
(defsystem my-app
  :class tycl/asdf:tycl-system
  :defsystem-depends-on (#:tycl)
  :depends-on ("my-library")   ; another tycl-system project
  :components (...))
```

When running `tycl transpile-all` or `tycl check-all`, dependency types are loaded from each dependency's `tycl-types.d.lisp` file. The type information file is located next to the dependency's `.asd` file and contains S-expressions describing all exported types (one entry per package). The file supports merge-on-write to accumulate type information across transpilations.

### Publishing a TyCL Library

When publishing a library written in TyCL, include `tycl-types.d.lisp` in your repository. Without this file, projects that depend on your library cannot type-check calls to your functions or classes.

```bash
# Generate tycl-types.d.lisp
tycl transpile-all my-library.asd

# Commit to your repository
git add tycl-types.d.lisp
git commit -m "Add type declaration file"
```

Although `tycl-types.d.lisp` is auto-generated during transpilation, it serves as the type declaration file for consumers of your library (similar to `.d.ts` in TypeScript) and should be checked into version control.

## Declaration Files for External Libraries

TyCL can type-check calls to external libraries that are not written in TyCL by using `.d.tycl` declaration files — similar to TypeScript's `.d.ts` files.

### Writing Declaration Files

Create a `tycl-declarations/` directory in your project root and place `.d.tycl` files in it. Each file declares type signatures using standard TyCL syntax, without function bodies:

```lisp
;;; tycl-declarations/cl-functions.d.tycl

(in-package #:common-lisp)

(defun [1+ :number] ([n :number]))
(defun [1- :number] ([n :number]))
(defun [zerop :boolean] ([n :number]))
(defun [length :integer] ([sequence :t]))
(defun [cons :cons] ([car :t] [cdr :t]))
(defun [first :t] ([list :t]))
(defun [reverse :list] ([sequence :list]))
(defun [string-upcase :string] ([string :string]))
```

You can also declare classes:

```lisp
;;; tycl-declarations/my-orm.d.tycl

(in-package #:my-orm)

(defclass db-connection ()
  (([host :string] :initarg :host)
   ([port :integer] :initarg :port)))

(defun [connect db-connection] ([host :string] [port :integer]))
(defun [query :list] ([conn db-connection] [sql :string]))
```

### Installing Community Declarations

Use `tycl install` to download pre-made declaration files from the [tycl-declarations](https://github.com/tamurashingo/tycl-declarations) repository:

```bash
tycl install common-lisp
tycl install cl-ppcre
```

This downloads files into `tycl-declarations/` in the current directory. See [tycl install](#tycl-install) for details.

### Discovery and Loading

Declaration files are automatically loaded during transpilation, type checking, and LSP server initialization. TyCL searches the following locations:

1. **Project-local**: `tycl-declarations/` directory relative to the source file or project root
2. **User-global**: `~/.config/tycl/declarations/` for declarations shared across projects

### Notes

- Use **canonical package names** in `in-package` (e.g., `#:common-lisp` instead of `#:cl`), because TyCL stores package names as written and the type checker uses canonical names for lookup.
- `&optional`, `&key`, and `&rest` parameters are supported in declaration files. For `&rest`, the type annotation specifies the element type (e.g., `&rest [args :string]`).
- Type parameter syntax uses `{T}` notation inside `[...]` annotations (e.g., `[identity {T} T]`).

See the [sample project](sample/tycl-declarations/) for a working example.

## Custom Macro Support

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

## LSP

TyCL provides a Language Server Protocol implementation for modern editor integration.

### Starting LSP Server

```bash
tycl lsp
```

### Editor Clients

#### VS Code

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

#### Emacs

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

#### Vim/Neovim

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

### LSP Features

- **Hover**: Show type information for symbols
- **Completion**: Context-aware code completion
- **Diagnostics**: Real-time type checking and error detection
- **Go to Definition**: Navigate to symbol definitions
- **Find References**: Locate all uses of a symbol
- **Document Symbols**: Outline view of file structure

### Startup Behavior

When the LSP server starts, it performs the following initialization:

1. **`.asd` file discovery**: Scans the workspace root for `.asd` files
2. **Full transpilation**: If `.asd` files with `tycl-system` definitions are found, all `.tycl` files in those systems are transpiled to generate `tycl-types.d.lisp`. This runs unconditionally regardless of whether `tycl-types.d.lisp` already exists, ensuring type information is always up-to-date.
3. **Declaration file loading**: Loads `.d.tycl` files from `tycl-declarations/` directories for external library type information
4. **Type information loading**: Loads `tycl-types.d.lisp` files from the workspace to populate the type cache

This ensures that LSP features (hover, completion, diagnostics) have complete type information available from the first interaction.

### Diagnostics Debounce

By default, diagnostics are debounced with a 500ms delay to avoid unnecessary CPU load during continuous typing. The debounce delay can be configured via the editor client:

- **VS Code**: `tycl.diagnostics.debounceMs` setting (0-5000ms, default: 500)
- **Other clients**: Send `diagnosticDebounceMs` in `initializationOptions`

Setting the value to `0` disables debouncing and computes diagnostics immediately on every change. File save always triggers diagnostics immediately regardless of the debounce setting.

See [docs/lsp-server.md](docs/lsp-server.md) for implementation details.

## Lisp API

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

;; Transpile a single file
(tycl:transpile-file "src/example.tycl" "src/example.lisp")

;; Transpile a string
(tycl:transpile-string
  "(defun [add :integer] ([x :integer] [y :integer]) (+ x y))")

;; Check types in a file
(tycl:check-file "src/example.tycl")
;; => T (no errors) or NIL (errors found)

;; Check types in a string
(tycl:check-string "(defun [add :integer] ([x :integer]) x)")
;; => T
```

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
│   └── tycl-declarations/  # Declaration files for external libraries
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
