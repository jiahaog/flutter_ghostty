#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

TARGET_OS="macos"
TARGET_ARCH=""
OUT_DIR=""
FRAMEWORKS_DEST=""
MACOS_MIN_VERSION="10.15"

print_usage() {
  cat <<'EOF'
Usage: build_native_deps.sh [options] [legacy_frameworks_dest]

Options:
  --target-os <os>             Target OS (currently only: macos)
  --target-arch <arch>         Target architecture (arm64 or x64)
  --out-dir <path>             Output directory for produced libraries
  --frameworks-dest <path>     Optional destination to mirror built dylibs
  --macos-min-version <ver>    Minimum macOS deployment version (default: 10.15)
  -h, --help                   Show this help message

Defaults:
  --target-os macos
  --target-arch host architecture
  --out-dir build/native/macos

The optional positional argument is kept for backward compatibility and maps to
--frameworks-dest.
EOF
}

require_value() {
  local flag="$1"
  local value="${2:-}"
  if [[ -z "$value" ]]; then
    echo "error: missing value for $flag" >&2
    exit 2
  fi
}

map_host_arch() {
  case "$(uname -m)" in
    arm64) echo "arm64" ;;
    x86_64) echo "x64" ;;
    *)
      echo "error: unsupported host architecture '$(uname -m)'" >&2
      exit 2
      ;;
  esac
}

zig_arch() {
  local arch="$1"
  case "$arch" in
    arm64) echo "aarch64" ;;
    x64) echo "x86_64" ;;
    *)
      echo "error: unsupported target arch '$arch'" >&2
      exit 2
      ;;
  esac
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target-os)
      require_value "$1" "${2:-}"
      TARGET_OS="$2"
      shift 2
      ;;
    --target-arch)
      require_value "$1" "${2:-}"
      TARGET_ARCH="$2"
      shift 2
      ;;
    --out-dir)
      require_value "$1" "${2:-}"
      OUT_DIR="$2"
      shift 2
      ;;
    --frameworks-dest)
      require_value "$1" "${2:-}"
      FRAMEWORKS_DEST="$2"
      shift 2
      ;;
    --macos-min-version)
      require_value "$1" "${2:-}"
      MACOS_MIN_VERSION="$2"
      shift 2
      ;;
    -h|--help)
      print_usage
      exit 0
      ;;
    -* )
      echo "error: unknown option '$1'" >&2
      print_usage >&2
      exit 2
      ;;
    *)
      if [[ -n "$FRAMEWORKS_DEST" ]]; then
        echo "error: unexpected positional argument '$1'" >&2
        print_usage >&2
        exit 2
      fi
      FRAMEWORKS_DEST="$1"
      shift
      ;;
  esac
done

if [[ -z "$TARGET_ARCH" ]]; then
  TARGET_ARCH="$(map_host_arch)"
fi

if [[ -z "$OUT_DIR" ]]; then
  OUT_DIR="$PROJECT_DIR/build/native/$TARGET_OS"
fi

require_command() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "error: required command '$cmd' is not available on PATH" >&2
    exit 127
  fi
}

require_command zig
require_command xcrun

if [[ "$TARGET_OS" != "macos" ]]; then
  echo "error: unsupported target OS '$TARGET_OS' (currently only 'macos')" >&2
  exit 2
fi

if [[ "$TARGET_ARCH" != "arm64" && "$TARGET_ARCH" != "x64" ]]; then
  echo "error: unsupported target arch '$TARGET_ARCH' (expected arm64 or x64)" >&2
  exit 2
fi

mkdir -p "$OUT_DIR"

ghostty_target="$(zig_arch "$TARGET_ARCH")-macos"
macos_sdk_path="$(xcrun --sdk macosx --show-sdk-path)"
if [[ -z "$macos_sdk_path" || ! -d "$macos_sdk_path" ]]; then
  echo "error: could not determine macOS SDK path via xcrun" >&2
  exit 1
fi

echo "[native] Building libghostty-vt via zig (target=$ghostty_target)"
(
  cd "$PROJECT_DIR/ghostty"
  zig build lib-vt -Demit-macos-app=false -Dtarget="$ghostty_target"
)

ghostty_lib_dir="$PROJECT_DIR/ghostty/zig-out/lib"
ghostty_versioned_name="$(basename "$(ls -t "$ghostty_lib_dir"/libghostty-vt.*.*.*.dylib 2>/dev/null | head -n1)")"
if [[ -z "$ghostty_versioned_name" ]]; then
  echo "error: could not locate versioned libghostty-vt dylib under $ghostty_lib_dir" >&2
  exit 1
fi

ghostty_versioned="$ghostty_lib_dir/$ghostty_versioned_name"

cp -f "$ghostty_versioned" "$OUT_DIR/$ghostty_versioned_name"
cp -f "$ghostty_versioned" "$OUT_DIR/libghostty-vt.dylib"
ln -sf libghostty-vt.dylib "$OUT_DIR/libghostty-vt.0.dylib"

echo "[native] Building libpty via clang (arch=$TARGET_ARCH, min=$MACOS_MIN_VERSION)"
xcrun --sdk macosx clang -dynamiclib \
  -arch "$(if [[ "$TARGET_ARCH" == "arm64" ]]; then echo arm64; else echo x86_64; fi)" \
  -isysroot "$macos_sdk_path" \
  -mmacosx-version-min="$MACOS_MIN_VERSION" \
  -o "$OUT_DIR/libpty.dylib" \
  "$PROJECT_DIR/native/pty.c" \
  -framework CoreFoundation \
  -lutil \
  -install_name @rpath/libpty.dylib

if [[ -n "$FRAMEWORKS_DEST" ]]; then
  echo "[native] Syncing dylibs to app Frameworks: $FRAMEWORKS_DEST"
  mkdir -p "$FRAMEWORKS_DEST"

  cp -f "$OUT_DIR/$ghostty_versioned_name" "$FRAMEWORKS_DEST/$ghostty_versioned_name"
  cp -f "$OUT_DIR/libghostty-vt.dylib" "$FRAMEWORKS_DEST/libghostty-vt.dylib"
  ln -sf libghostty-vt.dylib "$FRAMEWORKS_DEST/libghostty-vt.0.dylib"

  cp -f "$OUT_DIR/libpty.dylib" "$FRAMEWORKS_DEST/libpty.dylib"
fi

echo "[native] Built artifacts:"
ls -la "$OUT_DIR"/libghostty-vt* "$OUT_DIR/libpty.dylib"
