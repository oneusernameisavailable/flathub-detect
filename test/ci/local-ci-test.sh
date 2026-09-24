#!/usr/bin/env bash
# local-ci-test.sh — Run CI matrix locally with Docker

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

# Test scenarios to run locally (subset of CI matrix)
SCENARIOS=(
    "ubuntu:24.04:enabled-system"
    "ubuntu:22.04:enabled-system"
    "debian:12:enabled-system"
    "fedora:41:enabled-system"
    "archlinux/archlinux:latest:enabled-system"
    "alpine:3.20:enabled-user"
    "nixos/nixos:24.11:custom-installation"
)

run_test() {
    local image="$1"
    local scenario="$2"
    
    echo "=== Testing $image with scenario: $scenario ==="
    
    docker run --rm --privileged \
        -v "$PROJECT_ROOT:/src" \
        "$image" \
        /src/test/ci/validate-detection.sh "$scenario"
}

main() {
    echo "Running local CI tests for fx-flathub-detect.sh"
    echo "Project root: $PROJECT_ROOT"
    echo ""
    
    local failed=0
    for entry in "${SCENARIOS[@]}"; do
        IFS=':' read -r image scenario <<< "$entry"
        if run_test "$image" "$scenario"; then
            echo "✓ PASS: $image - $scenario"
        else
            echo "✗ FAIL: $image - $scenario"
            ((failed++))
        fi
        echo ""
    done
    
    if [[ $failed -eq 0 ]]; then
        echo "=== ALL TESTS PASSED ==="
        exit 0
    else
        echo "=== $failed TEST(S) FAILED ==="
        exit 1
    fi
}

main "$@"