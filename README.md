# Wry Zig Wrapper

Build system for creating Zig applications with Wry (Rust WebView library).

## Prerequisites

- Zig 0.15.0 or later
- Rust toolchain
- GTK 3 development libraries
- WebKitGTK 4.1 development libraries

On Ubuntu/Debian:
```bash
sudo apt install zig cargo libgtk-3-dev libwebkit2gtk-4.1-dev
```

## Building

### Build everything:
```bash
zig build
```

This will:
1. Compile the Rust library (wry) to `target/release/libwry_zig_wrapper.so`
2. Compile the Zig application to `zig-out/bin/wry_window_app`
3. Install both to `zig-out/` directory

### Run the application:
```bash
# Method 1: With manual LD_LIBRARY_PATH
LD_LIBRARY_PATH=zig-out/lib ./zig-out/bin/wry_window_app

# Method 2: Using zig build run (requires zig-out in PATH)
zig build run-local
```

## Structure

```
├── build.zig                 # Zig build system
├── Cargo.toml                # Rust package configuration
├── wry.zig                  # Zig wrapper module
├── test_app.zig             # Zig main application
├── src/lib.rs               # Rust FFI wrapper
├── target/release/
│   └── libwry_zig_wrapper.so  # Compiled Rust library
└── zig-out/
    ├── bin/
    │   └── wry_window_app   # Compiled Zig executable
    └── lib/
        └── libwry_zig_wrapper.so  # Installed Rust library
```

## Important Notes

### Zig 0.15 PLT/GOT Bug Fix

This project uses `-lc` flag to fix a critical bug in Zig 0.15 where
dynamic symbols were not properly resolved, causing segfaults at address 0x0.

The fix is applied automatically by the build system (see `exe.linkSystemLibrary("c")`).

Reference: https://github.com/ziglang/zig/issues/12010

### Dynamic Linking Only

**Static linking is not supported** because:
- GTK and WebKitGTK do not support static linking
- glibc is not designed for static linking (NSS, symbol versioning)
- Would require hundreds of megabytes of bundled libraries

The dynamic linking approach used here is:
- ✅ Works with Zig 0.15
- ✅ Uses system GTK/WebKit (no need to bundle)
- ✅ Small executable size
- ✅ Easy to distribute

## Distribution

When distributing your app, you need to ship:

1. The Zig executable: `zig-out/bin/wry_window_app`
2. The Rust library: `zig-out/lib/libwry_zig_wrapper.so`
3. Instructions to set `LD_LIBRARY_PATH` to find the library

Example:
```bash
# Install to /opt/myapp/
cp zig-out/bin/wry_window_app /opt/myapp/
cp zig-out/lib/libwry_zig_wrapper.so /opt/myapp/

# Users run with:
LD_LIBRARY_PATH=/opt/myapp /opt/myapp/wry_window_app
```

## Development

To use in your own Zig project:

1. Copy `wry.zig` to your project
2. Add to your `build.zig`:
   ```zig
   const wry_module = b.createModule(.{
       .root_source_file = b.path("wry.zig"),
   });
   exe.root_module.addImport("wry", wry_module);
   
   exe.linkSystemLibrary("wry_zig_wrapper");
   exe.addLibraryPath(.{ .cwd_relative = "path/to/target/release" });
   exe.linkSystemLibrary("c"); // IMPORTANT: Fix for Zig 0.15
   ```

## License

This wrapper is MIT licensed. The underlying wry library is also MIT licensed.
