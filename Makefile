.PHONY: test test.unit test.cli test.sample clean clean.cli help install

# Default target
help:
	@echo "TyCL - Typed Common Lisp"
	@echo ""
	@echo "Available targets:"
	@echo "  make test        - Run all tests (unit + cli + sample)"
	@echo "  make test.unit   - Run unit tests via ASDF test-op"
	@echo "  make test.cli    - Run CLI integration tests"
	@echo "  make test.sample - Run sample project (run + test)"
	@echo "  make install     - Install tycl command (requires roswell)"
	@echo "  make clean       - Clean compiled files"
	@echo "  make clean.cli   - Clean generated lisp files from CLI tests"
	@echo "  make help        - Show this help message"

# Run all tests (unit + cli + sample)
test: test.unit test.cli test.sample

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
	@echo ""
	@echo "=== Part 1: Direct API test (existing) ==="
	@for tycl_file in test/cli/*.tycl; do \
		echo ""; \
		echo "Testing $$tycl_file"; \
		lisp_file=$${tycl_file%.tycl}.lisp; \
		types_file=$${tycl_file%.tycl}.tycl-types; \
		CL_SOURCE_REGISTRY="$$PWD//:$${CL_SOURCE_REGISTRY}" \
			ros run --noinform \
			        --eval "(push #P\"$$PWD/\" asdf:*central-registry*)" \
			        --eval '(ql:quickload :tycl :silent t)' \
			        --eval "(tycl:transpile-file \"$$tycl_file\" nil :extract-types t :save-types t)" \
			        --quit || exit 1; \
		if [ ! -f "$$lisp_file" ]; then \
			echo "Error: Transpiled file $$lisp_file not found"; \
			exit 1; \
		fi; \
		if [ ! -f "$$types_file" ]; then \
			echo "Error: Type info file $$types_file not found"; \
			exit 1; \
		fi; \
		echo "✓ Generated $$lisp_file"; \
		echo "✓ Generated $$types_file"; \
		ros run --noinform --load "$$lisp_file" --quit || exit 1; \
	done
	@echo ""
	@echo "=== Part 2: Roswell script test ==="
	@test_file=test/cli/basic-types.tycl; \
	lisp_file=$${test_file%.tycl}.lisp; \
	types_file=$${test_file%.tycl}.tycl-types; \
	rm -f "$$lisp_file" "$$types_file"; \
	echo "Testing: ros roswell/tycl.ros transpile $$test_file"; \
	CL_SOURCE_REGISTRY="$$PWD//:$${CL_SOURCE_REGISTRY}" \
		ros roswell/tycl.ros transpile "$$test_file" || exit 1; \
	if [ ! -f "$$lisp_file" ]; then \
		echo "Error: Roswell script did not generate $$lisp_file"; \
		exit 1; \
	fi; \
	if [ ! -f "$$types_file" ]; then \
		echo "Error: Roswell script did not generate $$types_file"; \
		exit 1; \
	fi; \
	echo "✓ Roswell script generated $$lisp_file"; \
	echo "✓ Roswell script generated $$types_file"; \
	echo ""; \
	echo "Testing: ros roswell/tycl.ros check $$test_file"; \
	CL_SOURCE_REGISTRY="$$PWD//:$${CL_SOURCE_REGISTRY}" \
		ros roswell/tycl.ros check "$$test_file" || exit 1; \
	echo "✓ Check command passed"
	@echo ""
	@echo "All CLI tests passed!"

# Run sample project (make run + make test)
test.sample:
	@echo "Running sample project..."
	@echo "=== run ========================================"
	@$(MAKE) -C sample
	@echo "=== unit test ========================================"
	@$(MAKE) -C sample test
	@echo "=== transpile ========================================"
	@$(MAKE) -C sample transpile-all
	@echo "=== type check ========================================"
	@$(MAKE) -C sample check-all

# Clean generated lisp files from CLI tests
clean.cli:
	@echo "Cleaning generated files from CLI tests..."
	@rm -f test/cli/*.lisp
	@rm -f test/cli/*.tycl-types
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
