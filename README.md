# flutter_ghostty

Flutter Embedder for `libghostty`.

Taking reference from https://github.com/ghostty-org/ghostling.

All code is written here by AI.

## Requirements

- **macOS** (currently the only supported platform)
- **Zig 0.15.2** - Required for building libghostty
- **Flutter SDK**
- **Xcode Command Line Tools**

## Setup & Build

### 1. Clone the repository with submodules

```bash
git clone --recursive https://github.com/jiahaog/flutter_ghostty.git
cd flutter_ghostty
```

If you've already cloned without `--recursive`, fetch the submodules:

```bash
git submodule update --init --recursive
```

### 2. Install Zig toolchain

Install Zig version `0.15.2` and ensure it is on your `PATH`.

### 3. Build libghostty

```bash
./scripts/build_libghostty.sh
```

This generates:
- Shared library used by the app: `ghostty/zig-out/lib/libghostty-vt.dylib`
- Headers: `ghostty/zig-out/include/ghostty/vt.h`

### 4. Build PTY helper

```bash
mkdir -p macos/Libs
clang -shared -o macos/Libs/libpty.dylib native/pty.c \
  -framework CoreFoundation -lutil \
  -install_name @rpath/libpty.dylib
```

### 5. Generate Dart FFI bindings

```bash
dart run ffigen --config ffigen.yaml
```

### 6. Run the app

Currently only works on macOS.

```bash
flutter run
```
