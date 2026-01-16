#include <stdint.h>

// Direct pointer to Rust function (same calling convention)
extern int32_t (*wry_test_simple_ptr)(void);

int32_t rust_call_shim(void) {
    return wry_test_simple_ptr();
}
