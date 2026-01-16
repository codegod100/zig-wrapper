#[no_mangle]
pub extern "cdecl" fn wry_test_cdecl() -> i32 {
    42
}

#[no_mangle]
pub extern "stdcall" fn wry_test_stdcall() -> i32 {
    43
}

#[no_mangle]
pub extern "fastcall" fn wry_test_fastcall() -> i32 {
    44
}
