#!/usr/bin/env bash
set -euo pipefail

# Spectra Linux Build Script
# Usage: ./scripts/build.sh [release|debug|clean|native|run]

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

case "${1:-release}" in
    release)
        flutter build linux --release
        ;;
    debug)
        flutter build linux --debug
        ;;
    native)
        build_native
        ;;
    clean)
        flutter clean
        rm -rf native/ort_bridge/build native/preprocess/build
        ;;
    run)
        flutter run -d linux
        ;;
    *)
        echo "Usage: $0 [release|debug|native|clean|run]"
        exit 1
        ;;
esac
