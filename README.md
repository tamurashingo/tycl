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
(defun [process :void] ([value (:integer | :string)])
  (typecase value
    (integer (handle-number value))
    (string (handle-string value))))
```

### Generics (Collection Types)

Data structures with type parameters:

```lisp
;; Specify element type for lists
(defun [sum-list :integer] ([nums (:list :integer)])
  (reduce #'+ nums :initial-value 0))

;; Hash tables
(defun [lookup (:string | :null)] 
       ([table (:hash-table :string :string)]
        [key :string])
  (gethash key table))
```

### Type Aliases

Reusable type definitions:

```lisp
(deftype-alias UserID :integer)
(deftype-alias (Maybe <T>) (T | :null))
(deftype-alias (Result <T E>) (:ok T) | (:error E))

(defun [find-user (Maybe User)] ([id UserID])
  (lookup-database id))
```

## Available Types

### Basic Types

- **Numbers**: `:integer`, `:float`, `:double-float`, `:rational`, `:number`, etc.
- **Strings**: `:string`, `:character`, `:simple-string`
- **Sequences**: `:list`, `:vector`, `:array`, `:cons`
- **Logic**: `:boolean`, `:symbol`, `:keyword`
- **Control**: `:void` (no return value), `:null`, `:t` (any type)
- **Others**: `:function`, `:hash-table`, `:stream`, `:pathname`

## Usage

### Basic Usage

```lisp
;; Enable TyCL readtable
(tycl:enable)

;; Define typed function
(defun [fibonacci :integer] ([n :integer])
  (if (<= n 1)
      n
      (+ (fibonacci (- n 1))
         (fibonacci (- n 2)))))

;; Check type information
(tycl:get-type-info 'fibonacci)
;; => (:function (:integer) :integer)
```

### LSP Integration ????

```json
// .vscode/settings.json (example)
{
  "tycl.lsp.enabled": true,
  "tycl.typeChecking": "strict"
}
```

## License

MIT
