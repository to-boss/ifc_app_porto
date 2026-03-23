# Building the Rust Library for Android

The Android app requires `libifc_ar_core.so` compiled for Android targets.
Place the compiled `.so` files in `app/src/main/jniLibs/<abi>/`.

## Prerequisites

1. Install Rust: https://rustup.rs/
2. Install Android NDK (via Android Studio → SDK Manager → SDK Tools → NDK)
3. Add Android targets to Rust:

```bash
rustup target add aarch64-linux-android    # ARM64 (modern devices)
rustup target add armv7-linux-androideabi  # ARMv7 (older devices)
rustup target add x86_64-linux-android     # x86_64 (emulator)
```

4. Configure NDK in `~/.cargo/config.toml`:

```toml
[target.aarch64-linux-android]
linker = "<NDK_PATH>/toolchains/llvm/prebuilt/windows-x86_64/bin/aarch64-linux-android21-clang.cmd"

[target.armv7-linux-androideabi]
linker = "<NDK_PATH>/toolchains/llvm/prebuilt/windows-x86_64/bin/armv7a-linux-androideabi21-clang.cmd"

[target.x86_64-linux-android]
linker = "<NDK_PATH>/toolchains/llvm/prebuilt/windows-x86_64/bin/x86_64-linux-android21-clang.cmd"
```

Replace `<NDK_PATH>` with your NDK path (e.g. `C:/Users/fabie/AppData/Local/Android/Sdk/ndk/26.1.10909125`).

## Build

From the Rust workspace root (`C:\Users\fabie\Hackathon\ifc_app_porto\rust`):

```bash
# ARM64 (most important — modern Android devices)
cargo build --release --target aarch64-linux-android -p ifc-ar-core

# ARMv7
cargo build --release --target armv7-linux-androideabi -p ifc-ar-core

# x86_64 (emulator)
cargo build --release --target x86_64-linux-android -p ifc-ar-core
```

## Copy to Android project

```bash
# Create jniLibs directories
mkdir -p app/src/main/jniLibs/arm64-v8a
mkdir -p app/src/main/jniLibs/armeabi-v7a
mkdir -p app/src/main/jniLibs/x86_64

# Copy .so files
cp ../rust/target/aarch64-linux-android/release/libifc_ar_core.so    app/src/main/jniLibs/arm64-v8a/
cp ../rust/target/armv7-linux-androideabi/release/libifc_ar_core.so  app/src/main/jniLibs/armeabi-v7a/
cp ../rust/target/x86_64-linux-android/release/libifc_ar_core.so     app/src/main/jniLibs/x86_64/
```

## UniFFI Kotlin Bindings

The Kotlin FFI bindings in `app/src/main/java/com/example/myapplication/ffi/IfcBridge.kt`
were written to match what UniFFI 0.26.x generates for the `ifc_ar_core` namespace.

If function names don't match, regenerate the bindings:

```bash
cd ../rust
cargo run --bin uniffi-bindgen generate \
  --library target/aarch64-linux-android/release/libifc_ar_core.so \
  --language kotlin \
  --out-dir ../android/app/src/main/java/uniffi/
```

Then update the import paths in the Android source files accordingly.

## Verifying function names

To check the actual exported symbol names in the compiled library:

```bash
# On Linux/Mac:
nm -D target/aarch64-linux-android/release/libifc_ar_core.so | grep uniffi

# On Windows (using NDK's llvm-nm):
<NDK_PATH>/toolchains/llvm/prebuilt/windows-x86_64/bin/llvm-nm.exe \
  target/aarch64-linux-android/release/libifc_ar_core.so | grep uniffi
```

Expected symbols:
- `uniffi_ifc_ar_core_fn_func_parse_and_export_glb`
- `uniffi_ifc_ar_core_fn_func_parse_ifc`
- `uniffi_ifc_ar_core_fn_func_export_combined_ifc`
- `uniffi_ifc_ar_core_fn_func_create_wall_mesh`
- `uniffi_ifc_ar_core_fn_func_export_combined_ifc_with_walls`
- `ffi_ifc_ar_core_rustbuffer_alloc`
- `ffi_ifc_ar_core_rustbuffer_free`
