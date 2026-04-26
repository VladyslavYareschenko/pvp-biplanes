#!/usr/bin/env bash
# build_ios_libs.sh
#
# Builds biplanes_core (static lib) as a universal fat binary:
#   - arm64  (iOS device)
#   - x86_64 (iOS Simulator on Intel Mac)
#   - arm64  (iOS Simulator on Apple Silicon Mac)
#
# Intended to be called by an Xcode "External Build System" target so that
# changes to core/*.cpp automatically trigger a rebuild before linking the
# iOS app.
#
# Usage (from repo root, or from Xcode build phase):
#   ./tools/build_ios_libs.sh [Debug|Release]
#
# Output:
#   build_ios/core/libbiplanes_core.a  ← universal fat library

set -euo pipefail

CONFIGURATION="${1:-Debug}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

BUILD_ARM64_DEVICE="$REPO_ROOT/build_ios_arm64_device"
BUILD_ARM64_SIM="$REPO_ROOT/build_ios_arm64_sim"
BUILD_X86_64_SIM="$REPO_ROOT/build_ios_x86_64_sim"
FAT_DIR="$REPO_ROOT/build_ios/core"

echo "[build_ios_libs] Configuration: $CONFIGURATION"
echo "[build_ios_libs] Repo root:      $REPO_ROOT"

# ---------------------------------------------------------------------------
# Helper: configure + build one slice
# ---------------------------------------------------------------------------
build_slice() {
    local BUILD_DIR="$1"
    local SYSROOT="$2"
    local ARCHS="$3"

    if [ ! -f "$BUILD_DIR/CMakeCache.txt" ]; then
        echo "[build_ios_libs] Configuring: sysroot=$SYSROOT arch=$ARCHS"
        cmake -S "$REPO_ROOT" -B "$BUILD_DIR" \
            -DCMAKE_SYSTEM_NAME=iOS \
            -DCMAKE_OSX_SYSROOT="$SYSROOT" \
            -DCMAKE_OSX_ARCHITECTURES="$ARCHS" \
            -DCMAKE_OSX_DEPLOYMENT_TARGET=15.0 \
            -DCMAKE_BUILD_TYPE="$CONFIGURATION"
    fi

    echo "[build_ios_libs] Building:    sysroot=$SYSROOT arch=$ARCHS"
    cmake --build "$BUILD_DIR" --config "$CONFIGURATION" --target biplanes_core
}

# ---------------------------------------------------------------------------
# Build all slices
# ---------------------------------------------------------------------------
build_slice "$BUILD_ARM64_DEVICE" "iphoneos"        "arm64"
build_slice "$BUILD_X86_64_SIM"   "iphonesimulator" "x86_64"

# arm64 simulator (Apple Silicon Macs)
build_slice "$BUILD_ARM64_SIM"    "iphonesimulator" "arm64"

# ---------------------------------------------------------------------------
# Combine into a single fat library
# Lipo cannot have two arm64 slices from different sysroots in the same
# flat .a — instead we create a simulator-only fat, then output the device
# lib alongside it. For building in Xcode, ONLY_ACTIVE_ARCH means only the
# relevant slice is used anyway.
#
# For a proper xcframework see the comment below; for now we output:
#   build_ios/core/libbiplanes_core.a        (arm64 device)
#   build_ios/core/libbiplanes_core_sim.a    (x86_64 + arm64 sim, fat)
#
# The Xcode project uses a pre-preprocessor macro or $(SDK_NAME) to pick
# the right lib, but that requires more setup.  The simplest approach that
# works with "ONLY_ACTIVE_ARCH=YES" (default for debug simulator builds):
# just build all three slices and let each build dir contain the right one.
# We expose them via xcframework so Xcode picks automatically.
# ---------------------------------------------------------------------------

echo "[build_ios_libs] Creating xcframework..."
mkdir -p "$REPO_ROOT/build_ios/core"

# Expose nlohmann_json headers at the path expected by the Xcode project
# (build_ios/_deps/nlohmann_json-src/include) without duplicating files.
mkdir -p "$REPO_ROOT/build_ios/_deps"
ln -sfn "$BUILD_ARM64_DEVICE/_deps/nlohmann_json-src" \
    "$REPO_ROOT/build_ios/_deps/nlohmann_json-src"

# Create simulator fat lib (x86_64 + arm64)
lipo -create \
    "$BUILD_X86_64_SIM/core/libbiplanes_core.a" \
    "$BUILD_ARM64_SIM/core/libbiplanes_core.a" \
    -output "$FAT_DIR/libbiplanes_core_sim.a"

# Copy device lib
cp "$BUILD_ARM64_DEVICE/core/libbiplanes_core.a" "$FAT_DIR/libbiplanes_core_device.a"

# Create xcframework
XCFW="$REPO_ROOT/build_ios/biplanes_core.xcframework"
rm -rf "$XCFW"
xcodebuild -create-xcframework \
    -library "$FAT_DIR/libbiplanes_core_device.a" \
    -headers "$REPO_ROOT/core/include" \
    -library "$FAT_DIR/libbiplanes_core_sim.a" \
    -headers "$REPO_ROOT/core/include" \
    -output "$XCFW"

echo "[build_ios_libs] Done → $XCFW"
