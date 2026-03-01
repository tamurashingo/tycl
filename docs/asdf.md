# TyCL ASDF Extension Design Document

## Overview

Define TyCL source files (`.tycl`) as components in ASDF's `defsystem`, and
deploy them to an output directory during `asdf:load-system` for compilation
and loading.

- `.tycl` files -- transpiled and placed as `.lisp` in the output directory
- `.lisp` files -- copied as-is to the output directory

ASDF compiles and loads the `.lisp` files in the output directory.
Source locations are specified using ASDF's standard `:pathname` and module
structure.

## Goals

- Allow `.tycl` files to be specified directly in `defsystem`
- Make `asdf:load-system` handle the entire transpile -> compile -> load pipeline
- Support mixed `.tycl` and `.lisp` files in the same system
- Keep generated files only in the output directory, making them easy to exclude from version control

## Usage

### Basic usage

```lisp
(defsystem my-app
  :class tycl-system
  :defsystem-depends-on (#:tycl)
  :tycl-output-dir "build/"
  :components
  ((:module "src"
    :components
    ((:tycl-file "main")
     (:tycl-file "utils" :depends-on ("main"))
     (:file "config")))))
```

With this definition:

| Source | Operation | Output |
|---|---|---|
| `src/main.tycl` | Transpile | `build/src/main.lisp` |
| `src/utils.tycl` | Transpile | `build/src/utils.lisp` |
| `src/config.lisp` | Copy | `build/src/config.lisp` |

ASDF compiles and loads from the `.lisp` files under `build/`.

### Controlling type information output

```lisp
(defsystem my-app
  :class tycl-system
  :defsystem-depends-on (#:tycl)
  :tycl-output-dir "build/"
  :tycl-extract-types t      ;; Extract type info (default: t)
  :tycl-save-types t         ;; Save type info to tycl-types.tmp (default: t)
  :components
  ((:module "src"
    :components
    ((:tycl-file "main")))))
```

## Design

### System class extension

Specify `:class tycl-system` in `defsystem`.
This class holds system-level settings such as the output directory.

Source locations are controlled via ASDF's standard `:pathname` and module
structure, so no dedicated source directory setting is needed.

```lisp
(defclass tycl-system (asdf:system)
  ((tycl-output-dir
    :initarg :tycl-output-dir
    :initform nil
    :accessor tycl-output-dir
    :documentation "Output directory for transpiled/copied files")
   (tycl-extract-types
    :initarg :tycl-extract-types
    :initform t
    :accessor tycl-extract-types-p
    :documentation "Whether to extract type information")
   (tycl-save-types
    :initarg :tycl-save-types
    :initform t
    :accessor tycl-save-types-p
    :documentation "Whether to save type info to tycl-types.tmp")
   (tycl-type-error-severity
    :initarg :tycl-type-error-severity
    :initform :warn
    :accessor tycl-type-error-severity
    :documentation "Type error handling: :ignore, :warn, or :error")))
```

### `:tycl-output-dir` base path

- Relative path: resolved against the directory containing the `.asd` file
- Absolute path: used as-is
- **nil (not specified): falls back to the system source directory**
  - Transpiled `.lisp` files are generated alongside the `.tycl` sources
  - `copy-source-op` is skipped when source and output are the same path

```lisp
(defun resolve-tycl-output-dir (system)
  "Resolve tycl-output-dir to an absolute pathname.
   When tycl-output-dir is nil, falls back to the system source directory."
  (let ((output-dir (tycl-output-dir system)))
    (if output-dir
        (if (uiop:absolute-pathname-p output-dir)
            (uiop:ensure-directory-pathname output-dir)
            (merge-pathnames
             (uiop:ensure-directory-pathname output-dir)
             (asdf:system-source-directory system)))
        (asdf:system-source-directory system))))
```

### Component classes

#### `tycl-file` (for `.tycl` files)

```lisp
(defclass tycl-file (asdf:cl-source-file)
  ()
  (:documentation "TyCL source file (.tycl). Transpiled to .lisp before compilation."))

(defmethod asdf:source-file-type ((c tycl-file) (s asdf:system))
  "tycl")
```

Referenced as `:tycl-file` in `defsystem`.

Source paths are resolved via ASDF's standard `component-pathname`
(based on module structure, `:pathname` specifications, etc.).

#### Component type registration

ASDF's `class-for-type` resolves `:tycl-file` by searching for the class
in `*package*` and `:asdf/interface`. Since `*package*` can be any package
depending on the `.asd` file's `in-package`, the `tycl-file` symbol is
imported into `asdf/interface`, `asdf`, and `asdf-user`.

```lisp
(dolist (pkg-name '(:asdf/interface :asdf :asdf-user))
  (let ((pkg (find-package pkg-name)))
    (when pkg
      (ignore-errors (import 'tycl-file pkg)))))
```

#### `:file` components (`.lisp` files)

Uses the standard `asdf:cl-source-file`.
Within a `tycl-system`, these are copied to the output directory.

### Custom operations

#### `transpile-tycl-op` (`.tycl` -> `.lisp`)

```lisp
(defclass transpile-tycl-op (asdf:downward-operation)
  ()
  (:documentation "Transpile .tycl files to .lisp in the output directory"))
```

#### `copy-source-op` (`.lisp` -> `.lisp` copy)

```lisp
(defclass copy-source-op (asdf:downward-operation)
  ()
  (:documentation "Copy .lisp source files to the output directory"))
```

### Output path resolution

Computes a relative path from the source location (`component-pathname`)
against the system source directory, and places the `.lisp` output under
the output directory.

#### `transpile-tycl-op` output (`.tycl` -> `build/*.lisp`)

```lisp
;; Output path: tycl-output-dir + relative path from source (extension changed to .lisp)
;; Example: src/main.tycl -> build/src/main.lisp
(defmethod asdf:output-files ((o transpile-tycl-op) (c tycl-file))
  (let* ((system (asdf:component-system c))
         (output-dir (resolve-tycl-output-dir system))
         (source-path (asdf:component-pathname c))
         (relative (enough-namestring source-path
                                      (asdf:system-source-directory system))))
    (values
     (list (merge-pathnames
            (make-pathname :type "lisp" :defaults relative)
            output-dir))
     t)))
```

#### `copy-source-op` output (`.lisp` -> `build/*.lisp`)

```lisp
;; Example: src/config.lisp -> build/src/config.lisp
(defmethod asdf:output-files ((o copy-source-op) (c asdf:cl-source-file))
  (let* ((system (asdf:component-system c))
         (output-dir (resolve-tycl-output-dir system))
         (source-path (asdf:component-pathname c))
         (relative (enough-namestring source-path
                                      (asdf:system-source-directory system))))
    (values
     (list (merge-pathnames relative output-dir))
     t)))
```

### Operation dependencies

#### `.tycl` files

```
transpile-tycl-op  ->  compile-op  ->  load-op
(.tycl -> build/*.lisp)  (build/*.lisp -> *.fasl)  (load .fasl)
```

```lisp
(defmethod asdf:component-depends-on ((o asdf:compile-op) (c tycl-file))
  `((transpile-tycl-op ,c) ,@(call-next-method)))

(defmethod asdf:input-files ((o asdf:compile-op) (c tycl-file))
  (list (first (asdf:output-files (make-instance 'transpile-tycl-op) c))))
```

#### `.lisp` files (within `tycl-system`)

```
copy-source-op  ->  compile-op  ->  load-op
(.lisp -> build/*.lisp)  (build/*.lisp -> *.fasl)  (load .fasl)
```

```lisp
(defmethod asdf:component-depends-on ((o asdf:compile-op) (c asdf:cl-source-file))
  ;; Only depend on copy-source-op for .lisp files within a tycl-system
  (if (typep (asdf:component-system c) 'tycl-system)
      `((copy-source-op ,c) ,@(call-next-method))
      (call-next-method)))

(defmethod asdf:input-files ((o asdf:compile-op) (c asdf:cl-source-file))
  ;; .lisp files in tycl-system compile from the output directory
  (if (typep (asdf:component-system c) 'tycl-system)
      (list (first (asdf:output-files (make-instance 'copy-source-op) c)))
      (call-next-method)))
```

Note: These methods specialize on `asdf:cl-source-file` but only affect
components within a `tycl-system` via the `typep` check. `tycl-file` is
a subclass of `asdf:cl-source-file`, but more specialized methods take
priority, so `.tycl` files are not affected.

### Perform methods

#### Transpilation

```lisp
(defmethod asdf:perform ((o transpile-tycl-op) (c tycl-file))
  (let* ((input-file (asdf:component-pathname c))
         (output-file (first (asdf:output-files o c)))
         (system (asdf:component-system c))
         (extract-types (tycl-extract-types-p system))
         (save-types (tycl-save-types-p system)))
    (ensure-directories-exist output-file)
    (tycl:transpile-file input-file output-file
                         :extract-types extract-types
                         :save-types save-types)))
```

#### Lisp source copy

Skips the copy when source and output are the same path
(i.e., when `:tycl-output-dir` is not specified).

```lisp
(defmethod asdf:perform ((o copy-source-op) (c asdf:cl-source-file))
  (let* ((input-file (asdf:component-pathname c))
         (output-file (first (asdf:output-files o c))))
    (unless (equal (truename input-file) (truename output-file))
      (ensure-directories-exist output-file)
      (uiop:copy-file input-file output-file))))
```

### Rebuild check

Re-execute only when the source file is newer than the output file.
`copy-source-op` always reports as done when source and output are the same path.

```lisp
(defmethod asdf:operation-done-p ((o transpile-tycl-op) (c tycl-file))
  (let ((source (asdf:component-pathname c))
        (output (first (asdf:output-files o c))))
    (and (probe-file output)
         (>= (file-write-date output)
             (file-write-date source)))))

(defmethod asdf:operation-done-p ((o copy-source-op) (c asdf:cl-source-file))
  (let ((source (asdf:component-pathname c))
        (output (first (asdf:output-files o c))))
    (or (equal source output)
        (and (probe-file output)
             (>= (file-write-date output)
                  (file-write-date source))))))
```

### Hooks (tycl-hooks.lisp)

`transpile-file` internally calls `find-and-load-hooks`, so no special
handling is needed on the ASDF extension side. If `tycl-hooks.lisp`
exists in the source file's directory, it is automatically loaded.

## File layout

The ASDF extension source code is located at:

```
src/
  asdf.lisp          ;; ASDF extension implementation
```

Added to `:components` in `tycl.asd`:

```lisp
(:file "asdf")  ;; placed after main.lisp
```

## Processing flow

```
User executes (asdf:load-system :my-app)
  |
  +-- ASDF scans the component list
  |
  +-- For :tycl-file components:
  |   |
  |   +-- 1. Execute transpile-tycl-op
  |   |     +-- Check operation-done-p for rebuild necessity
  |   |     +-- Read *.tycl
  |   |     +-- Call transpile-file
  |   |     |   +-- Auto-load tycl-hooks.lisp if present
  |   |     |   +-- Transpile TyCL -> CL
  |   |     |   +-- Save type info to tycl-types.tmp (if configured)
  |   |     +-- Output to build/*.lisp
  |   |
  |   +-- 2. Execute compile-op (input: build/*.lisp)
  |   |     +-- Generate .fasl
  |   |
  |   +-- 3. Execute load-op
  |         +-- Load .fasl
  |
  +-- For :file components (within tycl-system):
  |   |
  |   +-- 1. Execute copy-source-op
  |   |     +-- Check operation-done-p for recopy necessity
  |   |     +-- Copy *.lisp -> build/*.lisp (skip if same path)
  |   |
  |   +-- 2. Execute compile-op (input: build/*.lisp)
  |   |     +-- Generate .fasl
  |   |
  |   +-- 3. Execute load-op
  |         +-- Load .fasl
  |
  +-- :file in non-tycl-system: standard compile -> load
```

## Directory structure example

```
my-app/
  my-app.asd           ;; defsystem definition
  tycl-hooks.lisp       ;; Custom hooks (optional)
  src/                   ;; Source directory (specified via ASDF's :pathname / modules)
    main.tycl
    utils.tycl
    config.lisp
  build/                 ;; Output directory (:tycl-output-dir) -- .gitignore target
    src/
      main.lisp          ;; Generated by transpilation
      utils.lisp         ;; Generated by transpilation
      config.lisp        ;; Generated by copy
  .gitignore             ;; Include build/
```

## Decisions

### `tycl-types.tmp` file output location

- Project-level type information is saved to `tycl-types.tmp` (a single file per project)
- `transpile-all` outputs to the same directory as the `.asd` file
- Single-file `transpile` outputs to the current working directory
- The LSP server scans for `tycl-types.tmp` files in the workspace

### Type database scope

- The current global `*type-database*` is sufficient
- Keys in `*type-database*` are `(package . symbol)`, so different package names do not collide

### `load-source-op` support

- Supported
- `load-source-op` also depends on `transpile-tycl-op` / `copy-source-op`,
  redirecting input files to the `.lisp` in the output directory

#### `.tycl` files

```lisp
(defmethod asdf:component-depends-on ((o asdf:load-source-op) (c tycl-file))
  `((transpile-tycl-op ,c) ,@(call-next-method)))

(defmethod asdf:input-files ((o asdf:load-source-op) (c tycl-file))
  (list (first (asdf:output-files (make-instance 'transpile-tycl-op) c))))
```

#### `.lisp` files (within `tycl-system`)

```lisp
(defmethod asdf:component-depends-on ((o asdf:load-source-op) (c asdf:cl-source-file))
  (if (typep (asdf:component-system c) 'tycl-system)
      `((copy-source-op ,c) ,@(call-next-method))
      (call-next-method)))

(defmethod asdf:input-files ((o asdf:load-source-op) (c asdf:cl-source-file))
  (if (typep (asdf:component-system c) 'tycl-system)
      (list (first (asdf:output-files (make-instance 'copy-source-op) c)))
      (call-next-method)))
```

### Error handling

- Syntax errors and type errors are handled differently:
  - **Syntax errors**: Always signal an error (transpilation is impossible)
  - **Type errors**: Behavior controlled by a system-level parameter
    - `:ignore` -- Ignore
    - `:warn` -- Warn and continue
    - `:error` -- Signal an error and abort
- `:tycl-type-error-severity` parameter added to `tycl-system` (default: `:warn`)
- User-friendly error message design is a separate task (TODO)

### `:tycl-source-dir`

- Not needed; not provided
- Since `package-inferred-system` is not used, components are specified individually as `:file` or `:tycl-file`
- Source locations are controlled via ASDF's standard `:pathname` and module structure

### `copy-source-op` application to `:file` within `tycl-system`

- Uses `component-depends-on` / `input-files` methods specialized on `asdf:cl-source-file`,
  with a `(typep (asdf:component-system c) 'tycl-system)` check
- CLOS method dispatch gives priority to more specialized methods for `tycl-file`
  (a subclass of `asdf:cl-source-file`), so `.tycl` files are not affected
- For systems that are not `tycl-system`, the methods fall through to `call-next-method`,
  so there are no global side effects
- A dedicated component class (`tycl-lisp-file`) was considered but rejected,
  as it would prevent natural use of `:file`

### Forward declaration stub in `.asd` files

When ASDF reads a `.asd` file, the Lisp reader must resolve `tycl/asdf:tycl-system`
at read time. However, TyCL is loaded via `:defsystem-depends-on` at evaluation time,
so the `tycl/asdf` package does not yet exist at read time.

To work around this, a stub package is declared in the `.asd` file before `defsystem`:

```lisp
(unless (find-package :tycl/asdf)
  (defpackage #:tycl/asdf
    (:export #:tycl-system #:tycl-file)))
```

- When TyCL is not loaded: the stub package is created, allowing the reader to resolve symbols
- When TyCL is already loaded: `unless` skips, and the real package is used directly

### Rove compatibility patch (dirty patch)

Rove discovers test suites by looking up `asdf:component-pathname` (`.tycl`)
in its internal `*file-package*` hash table. However, the keys in this table
are set from `*load-pathname*` (`.fasl`) or `*compile-file-pathname*` (`.lisp`)
at load time, so tests in `.tycl` components are not discovered.

To address this, an `:after` method on `load-op` registers an additional
`.tycl` path mapping in `*file-package*`.

```lisp
(defmethod asdf:perform :after ((o asdf:load-op) (c tycl-file))
  ;; Only executes when rove is loaded
  ;; Adds .tycl path -> package mapping to *file-package*
  ...)
```

- When rove is not loaded: `find-package` returns nil, so nothing happens
- When rove's internals change: a warning is emitted via `warn`, but the build continues
- Accesses rove's internal symbol `rove/core/suite/file::*file-package*`,
  so it may break on rove version upgrades

#### `:tycl-output-dir` constraint when using rove

The rove test system must **not** set `:tycl-output-dir`.
If set, transpiled output is placed in a separate directory, and even though
the patch resolves the extension mismatch, the directory mismatch remains
and tests are not discovered.

```lisp
;; rove test system -- do NOT set :tycl-output-dir
(defsystem my-app/test
  :class tycl-system
  :defsystem-depends-on (#:tycl)
  ;; no :tycl-output-dir -- .lisp is generated next to .tycl source
  :depends-on ("my-app" "rove")
  ...)
```

## Open issues

### Compatibility with `package-inferred-system`

- Not supported at this time (future work)
- `tycl-system` inherits from `asdf:system`, and `package-inferred-system`
  is a separate lineage, so both cannot be specified via `:class` simultaneously
- To support this, a multiple-inheritance class `tycl-package-inferred-system`
  would need to be created, addressing the following challenges:
  - Auto-detection of `.tycl` files (normally only `.lisp` files are scanned)
  - Reading `defpackage` from `.tycl` files using the TyCL readtable
  - Automatic component class selection based on `.tycl` / `.lisp` extension
  - Consistency of output directory and path resolution logic
