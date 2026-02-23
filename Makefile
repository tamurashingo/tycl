.PHONY: test test.unit test.cli clean clean.cli help install

# Default target
help:
	@echo "TyCL - Typed Common Lisp"
	@echo ""
	@echo "Available targets:"
	@echo "  make test        - Run all tests (unit + cli)"
	@echo "  make test.unit   - Run unit tests via ASDF test-op"
	@echo "  make test.cli    - Run CLI integration tests"
	@echo "  make install     - Install tycl command (requires roswell)"
	@echo "  make clean       - Clean compiled files"
	@echo "  make clean.cli   - Clean generated lisp files from CLI tests"
	@echo "  make help        - Show this help message"

# Run all tests (unit + cli)
test: test.unit test.cli

# Run unit tests using ASDF test-op (calls the :in-order-to test defined in tycl.asd)
test.unit:
	@echo "Running TyCL unit tests via ASDF..."
	@CL_SOURCE_REGISTRY="$$PWD//:$${CL_SOURCE_REGISTRY}" \
		ros run --noinform \
		        --eval '(ql:quickload :tycl :silent t)' \
		        --eval '(asdf:test-system :tycl)' \
		        --quit

# Run CLI integration tests
test.cli: clean.cli
	@echo "Running TyCL CLI integration tests..."
	@for tycl_file in test/cli/*.tycl; do \
		echo ""; \
		echo "=== Testing $$tycl_file ==="; \
		lisp_file=$${tycl_file%.tycl}.lisp; \
		CL_SOURCE_REGISTRY="$$PWD//:$${CL_SOURCE_REGISTRY}" \
			ros run --noinform \
			        --eval "(push #P\"$$PWD/\" asdf:*central-registry*)" \
			        --eval '(ql:quickload :tycl :silent t)' \
			        --eval "(tycl:transpile-file \"$$tycl_file\")" \
			        --quit || exit 1; \
		if [ ! -f "$$lisp_file" ]; then \
			echo "Error: Transpiled file $$lisp_file not found"; \
			exit 1; \
		fi; \
		ros run --noinform --load "$$lisp_file" --quit || exit 1; \
	done
	@echo ""
	@echo "All CLI tests passed!"

# Clean generated lisp files from CLI tests
clean.cli:
	@echo "Cleaning generated lisp files from CLI tests..."
	@rm -f test/cli/*.lisp
	@echo "Done."

# Install tycl command using roswell
install:
	@echo "Installing tycl command..."
	@ros install roswell/tycl.ros
	@echo "Done. You can now use: tycl <command> [options]"
	@echo ""
	@echo "Examples:"
	@echo "  tycl transpile example.tycl"
	@echo "  tycl check example.tycl"
	@echo "  tycl help"

# Clean compiled files
clean: clean.cli
	@echo "Cleaning compiled files..."
	@find . -name '*.fasl' -delete
	@find . -name '*~' -delete
	@rm -rf .cache
	@echo "Done."
