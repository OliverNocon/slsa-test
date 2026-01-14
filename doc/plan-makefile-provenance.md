# SLSA Build Provenance for Makefile-Based Builds

This guide shows how to create SLSA build provenance for a Makefile-based build process.

## Overview

SLSA (Supply-chain Levels for Software Artifacts) provenance provides a way to document how software artifacts were built, including what sources were used, what build process was executed, and in what environment.

## Components

### 1. Makefile with SLSA Provenance Generation

The Makefile includes build targets and provenance generation:

```makefile
# Makefile
.PHONY: build clean provenance all

# Build variables
BINARY_NAME := myapp
BUILD_DIR := ./build
VERSION := $(shell git describe --tags --always --dirty)
COMMIT := $(shell git rev-parse HEAD)
BUILD_DATE := $(shell date -u +"%Y-%m-%dT%H:%M:%SZ")

# Compiler settings
GO := go
GOFLAGS := -trimpath -ldflags="-X main.Version=$(VERSION) -X main.Commit=$(COMMIT)"

all: clean build provenance

build:
	@echo "Building $(BINARY_NAME)..."
	@mkdir -p $(BUILD_DIR)
	$(GO) build $(GOFLAGS) -o $(BUILD_DIR)/$(BINARY_NAME) .
	@echo "Build complete: $(BUILD_DIR)/$(BINARY_NAME)"

provenance: build
	@echo "Generating SLSA provenance..."
	@./generate-provenance.sh $(BUILD_DIR)/$(BINARY_NAME)

clean:
	@rm -rf $(BUILD_DIR)
	@echo "Clean complete"
```

### 2. Provenance Generation Script

Shell script that generates SLSA v1.0 provenance:

```bash
#!/bin/bash
# generate-provenance.sh

set -e

ARTIFACT_PATH="$1"
ARTIFACT_NAME=$(basename "$ARTIFACT_PATH")

# Calculate SHA256 digest
DIGEST=$(shasum -a 256 "$ARTIFACT_PATH" | awk '{print $1}')

# Get build environment details
BUILD_TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
GIT_COMMIT=$(git rev-parse HEAD)
GIT_TAG=$(git describe --tags --always)
GIT_REPO=$(git config --get remote.origin.url)
BUILDER_ID="$(whoami)@$(hostname)"

# Get build command from history or environment
BUILD_COMMAND="make build"

# Create provenance file
cat > "${ARTIFACT_PATH}.provenance.json" << EOF
{
  "_type": "https://in-toto.io/Statement/v1",
  "subject": [
    {
      "name": "${ARTIFACT_NAME}",
      "digest": {
        "sha256": "${DIGEST}"
      }
    }
  ],
  "predicateType": "https://slsa.dev/provenance/v1",
  "predicate": {
    "buildDefinition": {
      "buildType": "https://example.com/Makefile@v1",
      "externalParameters": {
        "repository": "${GIT_REPO}",
        "ref": "${GIT_TAG}",
        "entryPoint": "Makefile"
      },
      "internalParameters": {
        "target": "build",
        "environment": {
          "GOOS": "${GOOS:-$(go env GOOS)}",
          "GOARCH": "${GOARCH:-$(go env GOARCH)}"
        }
      },
      "resolvedDependencies": [
        {
          "uri": "git+${GIT_REPO}",
          "digest": {
            "sha1": "${GIT_COMMIT}"
          }
        }
      ]
    },
    "runDetails": {
      "builder": {
        "id": "${BUILDER_ID}",
        "version": {
          "make": "$(make --version | head -n1)",
          "go": "$(go version)"
        }
      },
      "metadata": {
        "invocationId": "$(uuidgen)",
        "startedOn": "${BUILD_TIMESTAMP}",
        "finishedOn": "${BUILD_TIMESTAMP}"
      },
      "byproducts": []
    }
  }
}
EOF

echo "Provenance generated: ${ARTIFACT_PATH}.provenance.json"
```

### 3. GitHub Actions Integration Example

For CI/CD environments using SLSA Generic Generator with Makefile:

```yaml
# .github/workflows/build-with-makefile.yml
name: Build with Makefile and SLSA Provenance

on:
  push:
    tags:
      - 'v*'

jobs:
  build:
    runs-on: ubuntu-latest
    outputs:
      digest: ${{ steps.build.outputs.digest }}
    steps:
      - uses: actions/checkout@v4

      - name: Set up Go
        uses: actions/setup-go@v5
        with:
          go-version: '1.21'

      - name: Build with Make
        id: build
        run: |
          make build
          DIGEST=$(sha256sum build/myapp | awk '{print $1}')
          echo "digest=$DIGEST" >> "$GITHUB_OUTPUT"

      - name: Upload artifact
        uses: actions/upload-artifact@v4
        with:
          name: myapp
          path: build/myapp

  provenance:
    needs: [build]
    permissions:
      actions: read
      id-token: write
      contents: write
    uses: slsa-framework/slsa-github-generator/.github/workflows/generator_generic_slsa3.yml@v1.10.0
    with:
      base64-subjects: "${{ needs.build.outputs.digest }}"
      upload-assets: true
```

### 4. Simplified Local Provenance Generation

For quick local testing without separate scripts:

```makefile
# Add to your Makefile
provenance-simple:
	@echo "Generating simple provenance..."
	@DIGEST=$$(shasum -a 256 $(BUILD_DIR)/$(BINARY_NAME) | awk '{print $$1}') && \
	echo '{ \
	  "_type": "https://in-toto.io/Statement/v1", \
	  "subject": [{"name": "$(BINARY_NAME)", "digest": {"sha256": "'$$DIGEST'"}}], \
	  "predicateType": "https://slsa.dev/provenance/v1", \
	  "predicate": { \
	    "buildDefinition": { \
	      "buildType": "https://example.com/Makefile@v1", \
	      "externalParameters": {"source": "'$$(git remote get-url origin)'", "commit": "'$$(git rev-parse HEAD)'"} \
	    } \
	  } \
	}' | jq '.' > $(BUILD_DIR)/$(BINARY_NAME).provenance.json
	@echo "Provenance saved to $(BUILD_DIR)/$(BINARY_NAME).provenance.json"
```

## Key Components Explained

The SLSA provenance document contains:

### Subject
The artifact being built with its name and SHA256 digest:
```json
"subject": [
  {
    "name": "myapp",
    "digest": {
      "sha256": "abc123..."
    }
  }
]
```

### Predicate Type
Specifies the SLSA provenance schema version:
```json
"predicateType": "https://slsa.dev/provenance/v1"
```

### Build Definition
Details about the build:
- **buildType**: Identifies your build system (e.g., Makefile)
- **externalParameters**: Input parameters like repository, ref, entrypoint
- **internalParameters**: Build-specific configuration
- **resolvedDependencies**: Source materials and dependencies used

### Run Details
Information about the build execution:
- **builder**: Who/what performed the build (ID and version info)
- **metadata**: Build invocation details (invocation ID, timestamps)
- **byproducts**: Additional outputs from the build process

## SLSA Levels

This approach can achieve different SLSA levels:
- **SLSA Level 1**: Basic provenance generation (manual, documented build)
- **SLSA Level 2**: Provenance with versioned build service (CI/CD)
- **SLSA Level 3**: Provenance from hardened, isolated build platform (GitHub Actions with hosted runners)

## Usage Instructions

1. Create the Makefile in your project root
2. Create the `generate-provenance.sh` script and make it executable
3. Run `make all` to build and generate provenance
4. The provenance will be saved alongside your binary

## Example Output

After running `make all`, you'll have:
```
build/
├── myapp
└── myapp.provenance.json
```

The provenance file can be used for:
- Supply chain security verification
- Compliance requirements
- Audit trails
- Reproducible builds validation
