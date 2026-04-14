.PHONY: all build test vet lint clean

BINARY_NAME=bin/flux-tui
MAIN_PATH=./cmd/flux-tui

all: clean build test

build:
	@mkdir -p bin
	go build -o $(BINARY_NAME) $(MAIN_PATH)

test:
	go test ./... -v

vet:
	go vet ./...

lint: vet
	@echo "Checking gofmt..."
	@if [ -n "$$(gofmt -l .)" ]; then \
		echo "gofmt: files not formatted:"; \
		gofmt -l .; \
		exit 1; \
	fi
	@echo "All files are properly formatted."

clean:
	rm -rf bin/
