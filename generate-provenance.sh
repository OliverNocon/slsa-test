#!/bin/bash
# generate-provenance.sh
# Generates SLSA v1.0 provenance for build artifacts

set -e

# Check if artifact path is provided
if [ -z "$1" ]; then
    echo "Error: No artifact path provided"
    echo "Usage: $0 <artifact-path>"
    exit 1
fi

ARTIFACT_PATH="$1"

# Check if artifact exists
if [ ! -f "$ARTIFACT_PATH" ]; then
    echo "Error: Artifact not found at $ARTIFACT_PATH"
    exit 1
fi

ARTIFACT_NAME=$(basename "$ARTIFACT_PATH")

echo "Generating SLSA provenance for: $ARTIFACT_NAME"

# Calculate SHA256 digest
DIGEST=$(shasum -a 256 "$ARTIFACT_PATH" | awk '{print $1}')
echo "  Digest: $DIGEST"

# Get build environment details
BUILD_TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
GIT_COMMIT=$(git rev-parse HEAD 2>/dev/null || echo "unknown")
GIT_TAG=$(git describe --tags --always 2>/dev/null || echo "dev")
GIT_REPO=$(git config --get remote.origin.url 2>/dev/null || echo "local")
BUILDER_ID="$(whoami)@$(hostname)"

# Get Go environment if available
GOOS_VAL="${GOOS:-$(go env GOOS 2>/dev/null || echo "unknown")}"
GOARCH_VAL="${GOARCH:-$(go env GOARCH 2>/dev/null || echo "unknown")}"

# Get tool versions
MAKE_VERSION=$(make --version 2>/dev/null | head -n1 || echo "make version unknown")
GO_VERSION=$(go version 2>/dev/null || echo "go version unknown")

# Generate UUID for invocation ID (fallback if uuidgen not available)
if command -v uuidgen >/dev/null 2>&1; then
    INVOCATION_ID=$(uuidgen)
else
    INVOCATION_ID="$(date +%s)-$$-$RANDOM"
fi

echo "  Builder: $BUILDER_ID"
echo "  Commit: $GIT_COMMIT"
echo "  Tag: $GIT_TAG"

# Create provenance file
PROVENANCE_FILE="${ARTIFACT_PATH}.provenance.json"

cat > "$PROVENANCE_FILE" << EOF
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
        "entryPoint": "Makefile",
        "target": "build"
      },
      "internalParameters": {
        "environment": {
          "GOOS": "${GOOS_VAL}",
          "GOARCH": "${GOARCH_VAL}"
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
          "make": "${MAKE_VERSION}",
          "go": "${GO_VERSION}"
        }
      },
      "metadata": {
        "invocationId": "${INVOCATION_ID}",
        "startedOn": "${BUILD_TIMESTAMP}",
        "finishedOn": "${BUILD_TIMESTAMP}"
      },
      "byproducts": []
    }
  }
}
EOF

echo ""
echo "Provenance generated successfully!"
echo "  File: $PROVENANCE_FILE"
echo ""
echo "To verify the provenance:"
echo "  cat $PROVENANCE_FILE | jq ."
