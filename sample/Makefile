CL_SOURCE_REGISTRY := $(CURDIR)/..//:$(CURDIR)//

.PHONY: all run test test.rove test.fiveam

all: run

test: test.rove test.fiveam

run:
	CL_SOURCE_REGISTRY="$(CL_SOURCE_REGISTRY)" \
	  ros run --noinform \
	    --eval '(ql:quickload :sample-project :silent t)' \
	    --eval '(sample-project/main:run)' \
	    --quit

test.rove:
	CL_SOURCE_REGISTRY="$(CL_SOURCE_REGISTRY)" \
	  rove sample-project.asd

test.fiveam:
	CL_SOURCE_REGISTRY="$(CL_SOURCE_REGISTRY)" \
	  ros run --noinform \
	    --eval '(ql:quickload :sample-project/test-fiveam :silent t)' \
	    --eval '(sample-project/test-fiveam:run-tests)' \
	    --quit
