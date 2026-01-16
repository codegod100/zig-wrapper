use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use std::ptr;
use tao::{
    event::{Event, WindowEvent},
    event_loop::{ControlFlow, EventLoop},
    window::WindowBuilder,
};
use wry::WebViewBuilder;

// Opaque pointer to WebView
#[repr(C)]
pub struct WebViewWrapper {
    _unused: i32,
}

// Callback function type for webview events
pub type EventCallback = extern "C" fn(event_type: i32, user_data: *mut std::ffi::c_void);

// Global state for the event loop
static mut EVENT_CALLBACK: Option<EventCallback> = None;
static mut USER_DATA: *mut std::ffi::c_void = ptr::null_mut();

/// Simple test function that returns integer
#[no_mangle]
pub extern "C" fn wry_test_simple() -> i32 {
    42
}

/// Export function pointer for Zig
#[no_mangle]
pub extern "C" fn wry_test_simple_ptr() -> *const fn() -> i32 {
    // Force function pointer type to avoid ambiguity
    unsafe { std::mem::transmute(wry_test_simple as *const fn() -> i32) }
}

/// Simple test function that takes and returns integer
#[no_mangle]
pub extern "C" fn wry_test_with_param(x: i32) -> i32 {
    x * 2
}

/// Simple test function that writes to pointer
#[no_mangle]
pub extern "C" fn wry_test_string(output: *mut u8, len: usize) -> i32 {
    if output.is_null() || len == 0 {
        return -1;
    }

    unsafe {
        let s = b"Hello from Rust!";
        let copy_len = std::cmp::min(s.len(), len - 1);
        std::ptr::copy_nonoverlapping(s.as_ptr(), output, copy_len);
        output.add(copy_len).write(0);
        copy_len as i32
    }
}

/// Create a webview and run the event loop (blocking call)
/// This is the simplest approach - creates webview and runs until window is closed
#[no_mangle]
pub extern "C" fn wry_create_and_run(url: *const c_char) {
    eprintln!("[DEBUG] Starting wry_create_and_run...");

    // Check if we have a display (avoid headless environments)
    #[cfg(target_os = "linux")]
    if std::env::var("DISPLAY").is_err() && std::env::var("WAYLAND_DISPLAY").is_err() {
        eprintln!("[DEBUG] No display available");
        eprintln!("Error: No display available. Set DISPLAY or WAYLAND_DISPLAY environment variable.");
        return;
    }

    eprintln!("[DEBUG] Display available, proceeding...");

    // Initialize GTK on Linux before creating window
    #[cfg(all(target_os = "linux", feature = "gtk"))]
    {
        eprintln!("[DEBUG] Initializing GTK...");
        if let Err(e) = gtk::init() {
            eprintln!("[DEBUG] GTK init failed: {}", e);
            eprintln!("Failed to initialize GTK: {}", e);
            return;
        }
        eprintln!("[DEBUG] GTK initialized successfully");
    }

    let url_str = unsafe {
        if url.is_null() {
            eprintln!("[DEBUG] URL is null, using default");
            String::from("https://www.example.com")
        } else {
            eprintln!("[DEBUG] Parsing URL from pointer: {:p}", url);
            CStr::from_ptr(url).to_string_lossy().into_owned()
        }
    };

    eprintln!("[DEBUG] URL: {}", url_str);

    eprintln!("[DEBUG] Creating event loop...");
    let event_loop = EventLoop::new();

    eprintln!("[DEBUG] Creating window...");
    let window = match WindowBuilder::new().build(&event_loop) {
        Ok(w) => {
            eprintln!("[DEBUG] Window created successfully");
            w
        }
        Err(e) => {
            eprintln!("[DEBUG] Failed to create window: {}", e);
            eprintln!("Failed to create window: {}", e);
            return;
        }
    };

    // Create webview
    #[cfg(any(target_os = "windows", target_os = "macos", target_os = "ios", target_os = "android"))]
    let _webview = WebViewBuilder::new()
        .with_url(&url_str)
        .build(&window)
        .unwrap();

    #[cfg(not(any(target_os = "windows", target_os = "macos", target_os = "ios", target_os = "android")))]
    let _webview = {
        use tao::platform::unix::WindowExtUnix;
        use wry::WebViewBuilderExtUnix;
        let vbox = window.default_vbox().unwrap();
        WebViewBuilder::new()
            .with_url(&url_str)
            .build_gtk(vbox)
            .unwrap()
    };

    // Run the event loop
    event_loop.run(move |event, _, control_flow| {
        *control_flow = ControlFlow::Wait;

        if let Event::WindowEvent {
            window_id: _,
            event: WindowEvent::CloseRequested,
            ..
        } = event
        {
            *control_flow = ControlFlow::Exit;
            unsafe {
                if let Some(callback) = EVENT_CALLBACK {
                    callback(1, USER_DATA); // 1 = CloseRequested event
                }
            }
        }

        #[cfg(all(target_os = "linux", feature = "gtk"))]
        while gtk::events_pending() {
            gtk::main_iteration_do(false);
        }
    });
}

/// Create a webview wrapper (non-blocking - simplified version)
/// In a full implementation, this would manage lifecycle separately
#[no_mangle]
pub extern "C" fn wry_create_webview(url: *const c_char) -> *mut WebViewWrapper {
    // For simplicity, just create a placeholder
    // The real implementation would need inter-thread communication
    let wrapper = Box::new(WebViewWrapper { _unused: 0 });
    Box::into_raw(wrapper)
}

/// Run the event loop (no-op in simplified version)
#[no_mangle]
pub extern "C" fn wry_run_event_loop(_wrapper: *mut WebViewWrapper) {
    // In the simplified version, the event loop runs in wry_create_and_run
}

/// Set a callback for webview events
#[no_mangle]
pub extern "C" fn wry_set_event_callback(
    callback: EventCallback,
    user_data: *mut std::ffi::c_void,
) {
    unsafe {
        EVENT_CALLBACK = Some(callback);
        USER_DATA = user_data;
    }
}

/// Destroy the webview wrapper
#[no_mangle]
pub extern "C" fn wry_destroy_webview(wrapper: *mut WebViewWrapper) {
    if !wrapper.is_null() {
        unsafe {
            let _ = Box::from_raw(wrapper);
        }
    }
}

/// Evaluate JavaScript (not implemented in simplified version)
#[no_mangle]
pub extern "C" fn wry_evaluate_script(
    _wrapper: *mut WebViewWrapper,
    _script: *const c_char,
) -> i32 {
    // Not implemented in simplified version
    -1
}

/// Set URL (not implemented in simplified version)
#[no_mangle]
pub extern "C" fn wry_set_url(_wrapper: *mut WebViewWrapper, _url: *const c_char) -> i32 {
    // Not implemented in simplified version
    -1
}

/// Get URL (not implemented in simplified version)
#[no_mangle]
pub extern "C" fn wry_get_url(
    _wrapper: *mut WebViewWrapper,
    _buffer: *mut c_char,
    _len: usize,
) -> i32 {
    // Not implemented in simplified version
    -1
}
