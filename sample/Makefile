CL_SOURCE_REGISTRY := $(CURDIR)/..//:$(CURDIR)//

# Exit with non-zero status on unhandled errors (CCL enters debugger by default)
ABORT_ON_ERROR := (setf *debugger-hook* (lambda (c h) (declare (ignore h)) (format *error-output* "~&Error: ~A~%" c) (uiop:quit 1)))

TYCL_CMD := $(CURDIR)/../roswell/tycl.ros

.PHONY: all run test test.rove test.fiveam clean transpile-all check-all

all: run

test: clean test.rove test.fiveam

clean:
	rm -rf build
	rm -f tycl-types.tmp
	rm -f src/math.lisp
	cd test-rove && for f in *.tycl; do rm -f "$${f%.tycl}.lisp"; done

run:
	CL_SOURCE_REGISTRY="$(CL_SOURCE_REGISTRY)" \
	  ros run --noinform \
	    --eval '$(ABORT_ON_ERROR)' \
	    --eval '(ql:quickload :sample-project :silent t)' \
	    --eval '(sample-project/main:run)' \
	    --quit

test.rove: clean
	CL_SOURCE_REGISTRY="$(CL_SOURCE_REGISTRY)" \
	  rove sample-project.asd

test.fiveam: clean
	CL_SOURCE_REGISTRY="$(CL_SOURCE_REGISTRY)" \
	  ros run --noinform \
	    --eval '$(ABORT_ON_ERROR)' \
	    --eval '(ql:quickload :sample-project/test-fiveam :silent t)' \
	    --eval '(sample-project/test-fiveam:run-tests)' \
	    --quit

transpile-all: clean
	CL_SOURCE_REGISTRY="$(CL_SOURCE_REGISTRY)" \
	  $(TYCL_CMD) transpile-all sample-project.asd

check-all: clean
	CL_SOURCE_REGISTRY="$(CL_SOURCE_REGISTRY)" \
	  $(TYCL_CMD) check-all sample-project.asd
