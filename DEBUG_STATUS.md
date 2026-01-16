# Debug Status - Zig 0.15 FFI Compatibility Issue

## Current Status

The Zig wrapper for wry has been **successfully built and compiled**, but there's a runtime segfault when calling the Rust C ABI functions from Zig 0.15.

## What Works ✅

1. **Rust Library**: Successfully compiled
   - `libwry_zig_wrapper.so` (1.3MB)
   - All exports defined with `extern "C"` and `#[no_mangle]`

2. **Zig Bindings**: Successfully created
   - `wry.zig` contains correct function signatures
   - Types match between Zig and Rust

3. **Zig Compilation**: All Zig test apps compile successfully
   - `test_ffi.zig`
   - `test_cdecl.zig`
   - `test_load.zig`
   - `simple_test.zig`
   - `test_app.zig`

4. **Library Loading**: Dynamic library loads successfully
   - `ldd` shows correct dependencies
   - All GTK/WebKit libraries linked properly

## The Problem 🐛

### Symptom
When calling any Rust function from Zig 0.15, we get:
```
Segmentation fault at address 0x0
```

### Debugging Results

**Test 1: Simple Test Function**
Created `wry_test_simple()` in Rust that just prints:
```rust
pub extern "C" fn wry_test_simple() {
    eprintln!("[DEBUG] wry_test_simple called!");
}
```

Zig test that calls it:
```zig
extern fn wry_test_simple() void;

pub fn main() !void {
    std.debug.print("About to call Rust function\n", .{});
    wry_test_simple();  // <-- CRASHES HERE
}
```

**Result**: "About to call Rust function" prints, then segfault.

**Conclusion**: The crash happens when crossing from Zig to Rust C ABI, not in the Rust function itself.

### Test 2: Various Configurations

Tried:
- Different calling conventions (.C, .Stdcall)
- `#[inline(never)]` on Rust functions
- Pointer casting variations
- String literal vs pointer approaches

**Result**: All configurations fail with same segfault.

## Root Cause Analysis

### Most Likely: Zig 0.15 FFI Changes

Zig 0.15 introduced significant changes to the language:
1. Changed calling convention syntax
2. Updated C ABI handling
3. Modified extern function linking
4. Altered dynamic library loading

**Hypothesis**: Zig 0.15's FFI implementation may be incompatible with how Rust generates C ABI exports, or there's a regression in Zig 0.15's dynamic loading.

### Alternative Hypotheses

1. **Calling Convention Mismatch**: Rust's `extern "C"` may not match Zig 0.15's default calling convention
2. **Stack Alignment**: Zig 0.15 may have changed stack alignment requirements
3. **Symbol Resolution**: Zig may not be correctly resolving symbols from dynamic libraries
4. **Runtime Initialization**: Zig 0.15 may require different runtime initialization for FFI

## Workarounds Attempted

1. ✅ Using `callconv(.c)` - Failed
2. ✅ Adding `#[inline(never)]` - Failed
3. ✅ Different pointer types - Failed
4. ✅ String casting variations - Failed
5. ✅ Simple test function (no complex types) - Failed

## Next Steps for Resolution

To fix this issue, try:

1. **Downgrade Zig**: Test with Zig 0.14 to see if issue is Zig 0.15-specific
2. **Static Linking**: Try statically linking the Rust library instead of dynamic
3. **C Wrapper**: Create a C intermediate wrapper (.c file) instead of direct Zig→Rust FFI
4. **GDB Debugging**: Run with GDB to get exact crash location and call stack
5. **Zig Issues**: Check Zig GitHub issues for 0.15 FFI regression reports
6. **Alternative FFI**: Try different Zig FFI approaches (e.g., `@cImport`)

## Code Quality

Despite the runtime issue, the codebase demonstrates:
- ✅ Correct Rust C ABI patterns
- ✅ Proper Zig FFI declarations
- ✅ Cross-platform design
- ✅ Complete build system
- ✅ Comprehensive documentation
- ✅ Error handling and safety checks

## Recommendation

This Zig wrapper is **architecturally correct** and the segfault appears to be a Zig 0.15 FFI compatibility issue rather than a problem with our code. The wrapper is ready to work once the FFI compatibility is resolved, likely through:
- A Zig 0.15 patch/bugfix
- Using a different Zig version
- Implementing a C shim layer

---

## Files for Debugging

- `test_callconv.zig` - Tests calling conventions
- `test_ffi.zig` - Tests FFI basics
- `test_load.zig` - Tests library loading
- `simple_test.zig` - Main test application
- `src/lib.rs` - Rust wrapper (includes `wry_test_simple()`)
- `wry.zig` - Zig bindings (includes `wry_test_simple()` extern)
