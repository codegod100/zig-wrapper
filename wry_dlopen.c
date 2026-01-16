#include <dlfcn.h>
#include <stdio.h>

int wry_test_simple(void);

int test_with_dlopen(void) {
    printf("Testing with dlopen...\n");
    
    void* handle = dlopen("lib/libwry_zig_wrapper.so", RTLD_NOW);
    if (!handle) {
        printf("Failed to open library!\n");
        return -1;
    }
    
    printf("Library opened successfully!\n");
    
    int (*func)(void) = dlsym(handle, "wry_test_simple");
    if (!func) {
        printf("Symbol not found!\n");
        dlclose(handle);
        return -1;
    }
    
    printf("Calling function...\n");
    int result = func();
    printf("Result: %d (expected 42)\n", result);
    
    dlclose(handle);
    return 0;
}
