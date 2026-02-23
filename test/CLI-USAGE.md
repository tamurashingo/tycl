# TyCL CLI Usage Examples

## Installation

```bash
# From project directory
make install

# Or directly with roswell
ros install roswell/tycl.ros
```

## Basic Commands

### 1. Transpile Command

```bash
# Transpile with default output (same directory, .lisp extension)
CL_SOURCE_REGISTRY="$(pwd):" ros roswell/tycl.ros transpile test/example.tycl

# Transpile with custom output path
CL_SOURCE_REGISTRY="$(pwd):" ros roswell/tycl.ros transpile test/example.tycl /tmp/output.lisp
```

**Output:**
- Reads `test/example.tycl` with type annotations
- Generates `test/example.lisp` (or specified path) without type annotations
- Standard Common Lisp code that runs on any implementation

### 2. Check Command

```bash
# Check type annotations in a file
CL_SOURCE_REGISTRY="$(pwd):" ros roswell/tycl.ros check test/example.tycl
```

**Output:**
- Exit code 0 if all types are valid
- Exit code 1 if type errors found
- Prints error details to stdout

### 3. Help Command

```bash
CL_SOURCE_REGISTRY="$(pwd):" ros roswell/tycl.ros help
```

## Example Workflow

```bash
# 1. Write TyCL code with type annotations
cat > myapp.tycl << 'TYCL'
(defun [greet :string] ([name :string])
  (format nil "Hello, ~A!" name))
TYCL

# 2. Check types
CL_SOURCE_REGISTRY="$(pwd):" ros roswell/tycl.ros check myapp.tycl

# 3. Transpile to Common Lisp
CL_SOURCE_REGISTRY="$(pwd):" ros roswell/tycl.ros transpile myapp.tycl

# 4. Use the generated .lisp file
sbcl --load myapp.lisp
```

## Integration with Build Systems

### Makefile Example

```makefile
.PHONY: transpile check

TYCL_FILES := $(wildcard src/*.tycl)
LISP_FILES := $(TYCL_FILES:.tycl=.lisp)

transpile: $(LISP_FILES)

%.lisp: %.tycl
CL_SOURCE_REGISTRY="$(PWD):" tycl transpile $< $@

check:
for f in $(TYCL_FILES); do \
CL_SOURCE_REGISTRY="$(PWD):" tycl check $$f || exit 1; \
done
```

## Notes

- **CL_SOURCE_REGISTRY**: Required when running from source (not installed)
- **After installation**: Can use `tycl` directly without CL_SOURCE_REGISTRY
- **File extensions**: `.tycl` for source, `.lisp` for generated files
