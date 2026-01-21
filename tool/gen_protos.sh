#!/usr/bin/env bash
set -euo pipefail

# Generates Dart protobuf and gRPC sources into lib/src/protos
# Usage: ./tool/gen_protos.sh /absolute/path/to/fabric-protos

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)
PROTOS=${1:-"/Users/srinath.n/github/fabric-protos"}
OUT_DIR=${ROOT_DIR}/lib/src/protos

if [ ! -d "$PROTOS" ]; then
  echo "Proto directory not found: $PROTOS"
  exit 1
fi

mkdir -p "$OUT_DIR"

echo "Generating Dart protos from $PROTOS into $OUT_DIR"

# Ensure protoc-gen-dart is available on PATH (install via `dart pub global activate protoc_plugin`)
protoc -I="$PROTOS" --dart_out=grpc:"$OUT_DIR" $(find "$PROTOS" -name "*.proto")

echo "Formatting generated files..."
if command -v dart >/dev/null 2>&1; then
  dart format "$OUT_DIR" || true
fi

echo "Done"