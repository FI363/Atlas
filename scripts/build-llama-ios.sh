#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# build-llama-ios.sh
#
# Clones llama.cpp, compiles a Metal-enabled static library for both
# iphoneos (arm64) and iphonesimulator (arm64 + x86_64), then packages
# them as a single xcframework at ios/LlamaFramework/llama.xcframework.
#
# Prerequisites (macOS only):
#   brew install cmake
#   Xcode + Command Line Tools installed
#
# Usage:
#   chmod +x scripts/build-llama-ios.sh
#   ./scripts/build-llama-ios.sh
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$REPO_ROOT/.llama_build"
LLAMA_SRC="$BUILD_DIR/llama.cpp"
OUT_DIR="$REPO_ROOT/ios/LlamaFramework"
XCFW="$OUT_DIR/llama.xcframework"

LLAMA_TAG="${LLAMA_TAG:-b5576}"          # pin a release tag; override with env
LLAMA_REPO="https://github.com/ggml-org/llama.cpp"

echo "=== Atlas llama.cpp iOS xcframework builder ==="
echo "    llama.cpp tag : $LLAMA_TAG"
echo "    output        : $XCFW"
echo ""

# ── 1. Clone / update source ─────────────────────────────────────────────────
mkdir -p "$BUILD_DIR"
if [ -d "$LLAMA_SRC/.git" ]; then
  echo ">> Updating existing llama.cpp clone..."
  git -C "$LLAMA_SRC" fetch --depth=1 origin "refs/tags/$LLAMA_TAG"
  git -C "$LLAMA_SRC" checkout "FETCH_HEAD"
else
  echo ">> Cloning llama.cpp @ $LLAMA_TAG..."
  git clone --depth 1 --branch "$LLAMA_TAG" "$LLAMA_REPO" "$LLAMA_SRC"
fi

# ── 2. Build for iphoneos (arm64) ────────────────────────────────────────────
echo ""
echo ">> Building for iphoneos (arm64)..."
DEVICE_BUILD="$BUILD_DIR/build-iphoneos"
cmake -S "$LLAMA_SRC" -B "$DEVICE_BUILD" \
  -G Xcode \
  -DCMAKE_SYSTEM_NAME=iOS \
  -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=16.0 \
  -DLLAMA_METAL=ON \
  -DLLAMA_BUILD_TESTS=OFF \
  -DLLAMA_BUILD_EXAMPLES=OFF \
  -DBUILD_SHARED_LIBS=OFF

cmake --build "$DEVICE_BUILD" \
  --config Release \
  -- -sdk iphoneos CODE_SIGNING_ALLOWED=NO

DEVICE_LIB=$(find "$DEVICE_BUILD" -name "libllama.a" -path "*/Release-iphoneos/*" | head -1)
DEVICE_HEADERS=$(find "$DEVICE_BUILD" -name "llama.h" | head -1)
if [ -z "$DEVICE_LIB" ]; then
  echo "ERROR: libllama.a not found for iphoneos" >&2; exit 1
fi

# ── 3. Build for iphonesimulator (arm64 + x86_64) ───────────────────────────
echo ""
echo ">> Building for iphonesimulator (arm64 + x86_64)..."
SIM_BUILD="$BUILD_DIR/build-iphonesimulator"
cmake -S "$LLAMA_SRC" -B "$SIM_BUILD" \
  -G Xcode \
  -DCMAKE_SYSTEM_NAME=iOS \
  -DCMAKE_OSX_ARCHITECTURES="arm64;x86_64" \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=16.0 \
  -DLLAMA_METAL=OFF \
  -DLLAMA_BUILD_TESTS=OFF \
  -DLLAMA_BUILD_EXAMPLES=OFF \
  -DBUILD_SHARED_LIBS=OFF

cmake --build "$SIM_BUILD" \
  --config Release \
  -- -sdk iphonesimulator CODE_SIGNING_ALLOWED=NO

SIM_LIB=$(find "$SIM_BUILD" -name "libllama.a" -path "*/Release-iphonesimulator/*" | head -1)
if [ -z "$SIM_LIB" ]; then
  echo "ERROR: libllama.a not found for iphonesimulator" >&2; exit 1
fi

# ── 4. Create xcframework ────────────────────────────────────────────────────
echo ""
echo ">> Creating xcframework..."
HEADERS_DIR="$BUILD_DIR/include"
mkdir -p "$HEADERS_DIR"
cp "$DEVICE_HEADERS" "$HEADERS_DIR/llama.h"

rm -rf "$XCFW"
mkdir -p "$OUT_DIR"

xcodebuild -create-xcframework \
  -library "$DEVICE_LIB"      -headers "$HEADERS_DIR" \
  -library "$SIM_LIB"         -headers "$HEADERS_DIR" \
  -output "$XCFW"

echo ""
echo "✅  Done: $XCFW"
echo ""
echo "Next steps:"
echo "  1. Open ios/Runner.xcworkspace in Xcode"
echo "  2. Add LlamaFramework/llama.xcframework to Runner → Frameworks, Libraries, and Embedded Content"
echo "  3. Set 'Embed & Sign' to 'Do Not Embed' (it's a static library)"
echo "  4. flutter run"
