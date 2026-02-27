CL_SOURCE_REGISTRY := $(CURDIR)/..//:$(CURDIR)//

# Exit with non-zero status on unhandled errors (CCL enters debugger by default)
ABORT_ON_ERROR := (setf *debugger-hook* (lambda (c h) (declare (ignore h)) (format *error-output* "~&Error: ~A~%" c) (uiop:quit 1)))

.PHONY: all run test test.rove test.fiveam

all: run

test: test.rove test.fiveam

run:
	CL_SOURCE_REGISTRY="$(CL_SOURCE_REGISTRY)" \
	  ros run --noinform \
	    --eval '$(ABORT_ON_ERROR)' \
	    --eval '(ql:quickload :sample-project :silent t)' \
	    --eval '(sample-project/main:run)' \
	    --quit

test.rove:
	CL_SOURCE_REGISTRY="$(CL_SOURCE_REGISTRY)" \
	  rove sample-project.asd

test.fiveam:
	CL_SOURCE_REGISTRY="$(CL_SOURCE_REGISTRY)" \
	  ros run --noinform \
	    --eval '$(ABORT_ON_ERROR)' \
	    --eval '(ql:quickload :sample-project/test-fiveam :silent t)' \
	    --eval '(sample-project/test-fiveam:run-tests)' \
	    --quit
