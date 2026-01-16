use std::ffi::CStr;
use std::os::raw::c_char;

/// Simple test function that returns integer
#[no_mangle]
pub extern "C" fn wry_test_simple() -> i32 {
    42
}

/// Export function pointer for Zig
#[no_mangle]
pub extern "C" fn wry_test_simple_ptr() -> *const fn() -> i32 {
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

    // Parse URL
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

    // Use wry::WebViewBuilder directly
    use wry::WebViewBuilder;
    
    #[cfg(not(any(target_os = "windows", target_os = "macos", target_os = "ios", target_os = "android")))]
    {
        use tao::event_loop::{ControlFlow, EventLoop};
        use tao::window::WindowBuilder;
        use tao::platform::unix::WindowExtUnix;
        use wry::WebViewBuilderExtUnix;

        // Initialize GTK
        #[cfg(feature = "gtk")]
        if let Err(e) = gtk::init() {
            eprintln!("[DEBUG] GTK init failed: {}", e);
            eprintln!("Failed to initialize GTK: {}", e);
            return;
        }

        let event_loop = EventLoop::new();
        let window = WindowBuilder::new().build(&event_loop).unwrap();
        let vbox = window.default_vbox().unwrap();
        
        let _webview = WebViewBuilder::new()
            .with_url(&url_str)
            .build_gtk(vbox)
            .unwrap();

        event_loop.run(move |event, _, control_flow| {
            *control_flow = ControlFlow::Wait;
            
            if let tao::event::Event::WindowEvent {
                event: tao::event::WindowEvent::CloseRequested,
                ..
            } = event
            {
                *control_flow = ControlFlow::Exit;
            }
        });
    }
    
    #[cfg(any(target_os = "windows", target_os = "macos", target_os = "ios", target_os = "android"))]
    {
        use tao::event_loop::{ControlFlow, EventLoop};
        use tao::window::WindowBuilder;

        let event_loop = EventLoop::new();
        let window = WindowBuilder::new().build(&event_loop).unwrap();
        
        let _webview = WebViewBuilder::new()
            .with_url(&url_str)
            .build(&window)
            .unwrap();

        event_loop.run(move |event, _, control_flow| {
            *control_flow = ControlFlow::Wait;
            
            if let tao::event::Event::WindowEvent {
                event: tao::event::WindowEvent::CloseRequested,
                ..
            } = event
            {
                *control_flow = ControlFlow::Exit;
            }
        });
    }
}
