# Sample Project

## Purpose

- Verify that TyCL integrates correctly with ASDF (`tycl-system`, `:tycl-file`)
- Confirm that test frameworks (rove, FiveAM) work with `.tycl` files

## Project Structure

```
sample/
  sample-project.asd       # System definition (tycl-system)
  src/
    math.tycl               # Typed arithmetic functions
    string-utils.tycl       # Typed string utilities
    config.lisp             # Configuration constants (plain .lisp)
    main.tycl               # Main logic using all modules
  test-rove/                # Tests using rove
  test-fiveam/              # Tests using FiveAM
  build/                    # Transpiler output (auto-generated, .gitignore'd)
```

## Forward Declaration Stub in .asd

When ASDF reads a `.asd` file, the Lisp reader must resolve
`tycl/asdf:tycl-system` **before** `:defsystem-depends-on` loads TyCL.
This is because the reader processes symbols at read time, while
`:defsystem-depends-on` is evaluated later.

To work around this, the `.asd` file creates a stub package if TyCL
is not yet loaded:

```lisp
(unless (find-package :tycl/asdf)
  (defpackage #:tycl/asdf
    (:export #:tycl-system #:tycl-file)))
```

This allows the reader to resolve `tycl/asdf:tycl-system` and
`tycl/asdf:tycl-file`. The real definitions are provided when
`:defsystem-depends-on` loads TyCL. If TyCL is already loaded,
the `unless` skips and the real package is used directly.

## Loading

### Quicklisp

```lisp
(push #P"/path/to/sample-project/" ql:*local-project-directories*)
(ql:quickload :sample-project)

(sample-project/main:run)
```

### ASDF

```lisp
;; Register the system (e.g., push to asdf:*central-registry*)
(push #P"/path/to/sample-project/" asdf:*central-registry*)
(asdf:load-system :sample-project)

(sample-project/main:run)
```

## Note on rove Test Module

### defsystem for rove

Unlike the main system or FiveAM tests, the rove test system must
**not** set `:tycl-output-dir`. This is because rove discovers test
suites by matching `asdf:component-pathname` (the `.tycl` source path)
against its internal file-to-package mapping. When `:tycl-output-dir`
is set, the transpiled `.lisp` files are placed in a separate directory
and the paths no longer match, causing rove to find 0 tests.

```lisp
;; Main system / FiveAM — use :tycl-output-dir to keep source clean
(defsystem sample-project
  :class tycl/asdf:tycl-system
  :tycl-output-dir "build/"    ; generated .lisp goes to build/
  ...)

;; rove — do NOT set :tycl-output-dir
(defsystem sample-project/test-rove
  :class tycl/asdf:tycl-system
  ;; no :tycl-output-dir — .lisp is generated next to .tycl source
  ...)
```

### .gitignore

Without `:tycl-output-dir`, transpiled `.lisp` and `.tycl-types` files
are generated alongside the source `.tycl` files in the same directory.
These generated files should not be committed.

Rather than adding each generated file individually to `.gitignore`,
it is simpler to write **all test files as `.tycl`** (even those
without type annotations) and ignore the entire directory's generated
outputs:

```gitignore
test-rove/*.lisp
test-rove/*.tycl-types
```

This way, only `.tycl` source files are tracked, and all generated
artifacts are excluded.

## Running Tests

### rove

Command line:

```bash
CL_SOURCE_REGISTRY="/path/to/sample-project//" rove sample-project.asd
```

REPL:

```lisp
(asdf:test-system :sample-project)
```

### FiveAM

REPL:

```lisp
(asdf:test-system :sample-project/test-fiveam)
```

Or directly:

```lisp
(ql:quickload :sample-project/test-fiveam)
(sample-project/test-fiveam:run-tests)
```
