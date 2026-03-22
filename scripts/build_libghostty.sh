#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_DIR/ghostty"
zig build lib-vt

echo "Built libghostty-vt at ghostty/zig-out/lib/"
ls -la zig-out/lib/libghostty-vt*
