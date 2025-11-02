#!/usr/bin/env bash
# Wrapper script for Gradle to build native libraries
# This script ensures the build runs in the correct nix-shell environment

set -e

# Get the script directory and project root
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "${SCRIPT_DIR}/.." && pwd )"

cd "$PROJECT_ROOT"

echo "=================================="
echo "Building Native Libraries"
echo "=================================="
echo "Project root: $PROJECT_ROOT"
echo ""

# Check if we're in a nix-shell already
if [ -n "$IN_NIX_SHELL" ]; then
    echo "Already in nix-shell, building directly..."
    make build-native
else
    echo "Not in nix-shell, entering nix-shell..."
    # Run make build-native inside nix-shell
    nix-shell --run "make build-native"
fi

echo ""
echo "=================================="
echo "Native libraries built successfully"
echo "=================================="
