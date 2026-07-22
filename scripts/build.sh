#!/usr/bin/env bash
set -euo pipefail

# Spectra Linux Build Script
# Usage: ./scripts/build.sh [release|debug|clean|native|package|run]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_DIR"

build_native() {
    echo "==> Building native C libraries for Linux..."

    echo "    Building ort_bridge..."
    mkdir -p native/ort_bridge/build
    cmake -S native/ort_bridge -B native/ort_bridge/build -DCMAKE_BUILD_TYPE=Release
    cmake --build native/ort_bridge/build

    echo "    Building nchw_preprocess..."
    mkdir -p native/preprocess/build
    cmake -S native/preprocess -B native/preprocess/build -DCMAKE_BUILD_TYPE=Release
    cmake --build native/preprocess/build

    echo "==> Native libraries built successfully."
}

copy_native_to_bundle() {
    local bundle_dir="$1"
    echo "==> Copying native libraries to bundle: $bundle_dir"
    mkdir -p "$bundle_dir/lib"

    if [ -f "native/ort_bridge/build/libort_bridge.so" ]; then
        cp -v "native/ort_bridge/build/libort_bridge.so" "$bundle_dir/lib/"
    fi
    if [ -f "native/preprocess/build/libnchw_preprocess.so" ]; then
        cp -v "native/preprocess/build/libnchw_preprocess.so" "$bundle_dir/lib/"
    fi
    echo "==> Native libraries copied."
}

case "${1:-release}" in
    release)
        build_native
        flutter build linux --release
        copy_native_to_bundle "build/linux/x64/release/bundle"
        echo "==> Linux release build complete."
        echo "    Bundle: build/linux/x64/release/bundle/"
        ;;
    debug)
        build_native
        flutter build linux --debug
        copy_native_to_bundle "build/linux/x64/debug/bundle"
        echo "==> Linux debug build complete."
        ;;
    package)
        # Full build + package into a tarball
        VERSION="${2:-$(cd "$PROJECT_DIR" && flutter pub run args 2>/dev/null || echo "unknown")}"
        bash "$0" release
        echo "==> Packaging release tarball..."
        cd build/linux/x64/release
        tar czf "$PROJECT_DIR/spectra-${VERSION}-linux-x64.tar.gz" bundle/
        cd "$PROJECT_DIR"
        echo "==> Package created: spectra-${VERSION}-linux-x64.tar.gz"
        ;;
    native)
        build_native
        ;;
    clean)
        flutter clean
        rm -rf native/ort_bridge/build native/preprocess/build
        ;;
    run)
        build_native
        flutter run -d linux
        ;;
    *)
        echo "Usage: $0 [release|debug|package|native|clean|run]"
        echo ""
        echo "  release   Build native libs + Flutter Linux release (default)"
        echo "  debug     Build native libs + Flutter Linux debug"
        echo "  package   Full build + create spectra-<version>-linux-x64.tar.gz"
        echo "  native    Build native C libraries only"
        echo "  clean     Remove all build artifacts"
        echo "  run       Build native libs + run on Linux"
        exit 1
        ;;
esac
