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

### 3. Fetch Dart packages

```bash
flutter pub get
```

### 4. Run or build the app

`flutter run -d macos` and `flutter build macos` invoke the package build hook
in `hook/build.dart`. That hook calls `scripts/build_native_deps.sh` to:

- build `libghostty-vt` via `zig build lib-vt -Demit-macos-app=false`
- build the PTY helper (`libpty.dylib`) via clang
- bundle both libraries as native assets for the macOS app

No custom macOS Xcode build phase or manual runpath setup is required.

```bash
flutter run -d macos
```

To produce a release build:

```bash
flutter build macos
```

### 5. Regenerate Dart FFI bindings

Regenerate the Ghostty bindings when `ghostty/vt.h` changes:

```bash
dart run ffigen --config ffigen.yaml
```

## Architecture

Native dependency orchestration now lives in Dart hooks and native assets,
not in custom macOS Runner build phases.

### Build flow

- `flutter run -d macos` and `flutter build macos` invoke `hook/build.dart`
- `hook/build.dart` detects the target platform and architecture, then runs
  `scripts/build_native_deps.sh`
- `scripts/build_native_deps.sh` builds `libghostty-vt` via Zig and `libpty`
  via `xcrun clang`
- the hook emits bundled `CodeAsset`s for the Dart libraries that declare the
  native bindings

### Runtime flow

- `lib/src/ghostty_bindings.g.dart` is generated with `ffigen` in `ffi-native`
  mode, so Ghostty symbols are declared with `@ffi.Native`
- `lib/src/pty_ffi.dart` also uses `@Native` declarations instead of
  `DynamicLibrary.open(...)`
- the hook emits assets named after those Dart library URIs, so Dart resolves
  symbols through Flutter's native-assets manifest at runtime
- `lib/src/terminal_state.dart` can call the bindings directly without
  platform-specific loading code

### Why The Xcode Project Still Exists

Flutter macOS apps still build through an Xcode host project, so
`macos/Runner.xcodeproj` remains. The difference is that the project no longer
owns the native dependency setup:

- the old custom Runner shell phase is removed
- custom linker flags and runpath tweaks are removed
- the remaining Flutter assemble wiring is standard Flutter host-project logic

### Why This Helps Future Platforms

When Android, iOS, or Linux support is added later, the main extension point is
still `hook/build.dart`. New platform branches can emit the same asset IDs for
platform-specific binaries, while the Dart binding and terminal code stays the
same.

## Optional: Build Native Dependencies Manually

You can still build the native libraries directly without launching Flutter.
The compatibility wrapper remains available:

```bash
./scripts/build_libghostty.sh
```

For direct access to the generalized script and its options:

```bash
./scripts/build_native_deps.sh --help
```

Manual builds default to writing artifacts under `build/native/macos/`.
