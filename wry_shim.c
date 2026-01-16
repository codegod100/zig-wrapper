#include <stdint.h>

// C shim to call Rust functions
int32_t wry_test_simple(void);

int32_t shim_test_simple(void) {
    return wry_test_simple();
}

int32_t shim_test_with_param(int32_t x) {
    extern int32_t wry_test_with_param(int32_t);
    return wry_test_with_param(x);
}

void wry_create_and_run(const char *url);

void shim_create_and_run(const char *url) {
    wry_create_and_run(url);
}
