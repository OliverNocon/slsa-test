.PHONY: build clean provenance provenance-simple all help

# Build variables
BINARY_NAME := myapp
BUILD_DIR := ./build
VERSION := $(shell git describe --tags --always --dirty 2>/dev/null || echo "dev")
COMMIT := $(shell git rev-parse HEAD 2>/dev/null || echo "unknown")
BUILD_DATE := $(shell date -u +"%Y-%m-%dT%H:%M:%SZ")

# Compiler settings
GO := go
GOFLAGS := -trimpath -ldflags="-X main.Version=$(VERSION) -X main.Commit=$(COMMIT) -X main.BuildDate=$(BUILD_DATE)"

# Default target
all: clean build provenance

help:
	@echo "Available targets:"
	@echo "  make build              - Build the binary"
	@echo "  make provenance         - Generate SLSA provenance (requires build first)"
	@echo "  make provenance-simple  - Generate simplified provenance inline"
	@echo "  make all                - Clean, build, and generate provenance"
	@echo "  make clean              - Remove build artifacts"
	@echo "  make help               - Show this help message"

build:
	@echo "Building $(BINARY_NAME)..."
	@mkdir -p $(BUILD_DIR)
	$(GO) build $(GOFLAGS) -o $(BUILD_DIR)/$(BINARY_NAME) .
	@echo "Build complete: $(BUILD_DIR)/$(BINARY_NAME)"
	@echo "Binary info:"
	@ls -lh $(BUILD_DIR)/$(BINARY_NAME)

provenance: build
	@echo "Generating SLSA provenance using script..."
	@chmod +x generate-provenance.sh
	@./generate-provenance.sh $(BUILD_DIR)/$(BINARY_NAME)

provenance-simple: build
	@echo "Generating simple provenance..."
	@DIGEST=$$(shasum -a 256 $(BUILD_DIR)/$(BINARY_NAME) | awk '{print $$1}') && \
	echo '{ \
	  "_type": "https://in-toto.io/Statement/v1", \
	  "subject": [{"name": "$(BINARY_NAME)", "digest": {"sha256": "'$$DIGEST'"}}], \
	  "predicateType": "https://slsa.dev/provenance/v1", \
	  "predicate": { \
	    "buildDefinition": { \
	      "buildType": "https://example.com/Makefile@v1", \
	      "externalParameters": {"source": "'$$(git remote get-url origin 2>/dev/null || echo "local")'", "commit": "'$$(git rev-parse HEAD 2>/dev/null || echo "unknown")'"}, \
	      "internalParameters": {"target": "build", "version": "$(VERSION)"} \
	    }, \
	    "runDetails": { \
	      "builder": {"id": "'$$(whoami)@$$(hostname)'"}, \
	      "metadata": {"invocationId": "'$$(uuidgen)'", "startedOn": "$(BUILD_DATE)"} \
	    } \
	  } \
	}' | jq '.' > $(BUILD_DIR)/$(BINARY_NAME).provenance-simple.json 2>/dev/null || \
	echo '{"_type": "https://in-toto.io/Statement/v1", "subject": [{"name": "$(BINARY_NAME)", "digest": {"sha256": "'$$DIGEST'"}}], "predicateType": "https://slsa.dev/provenance/v1"}' > $(BUILD_DIR)/$(BINARY_NAME).provenance-simple.json
	@echo "Simple provenance saved to $(BUILD_DIR)/$(BINARY_NAME).provenance-simple.json"

clean:
	@rm -rf $(BUILD_DIR)
	@echo "Clean complete"
