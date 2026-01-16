use std::ffi::CStr;
use std::os::raw::c_char;

/// Create a webview and run the event loop (blocking call)
#[no_mangle]
pub extern "C" fn wry_create_and_run(url: *const c_char) {
    eprintln!("[DEBUG] Starting wry_create_and_run...");

    // Check if we have a display (avoid headless environments)
    #[cfg(target_os = "linux")]
    if std::env::var("DISPLAY").is_err() && std::env::var("WAYLAND_DISPLAY").is_err() {
        eprintln!("[ERROR] No display available");
        return;
    }

    // Parse URL
    let url_str = unsafe {
        if url.is_null() {
            String::from("https://www.example.com")
        } else {
            CStr::from_ptr(url).to_string_lossy().into_owned()
        }
    };

    eprintln!("[DEBUG] URL: {}", url_str);

    use wry::WebViewBuilder;

    #[cfg(not(any(target_os = "windows", target_os = "macos", target_os = "ios", target_os = "android")))]
    {
        use tao::event_loop::{ControlFlow, EventLoop};
        use tao::window::WindowBuilder;
        use tao::platform::unix::WindowExtUnix;
        use wry::WebViewBuilderExtUnix;

        #[cfg(feature = "gtk")]
        if let Err(e) = gtk::init() {
            eprintln!("[ERROR] GTK init failed: {}", e);
            return;
        }

        let event_loop = EventLoop::new();
        let window = WindowBuilder::new().build(&event_loop).unwrap();
        let vbox = window.default_vbox().unwrap();

        let mut webview = WebViewBuilder::new()
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

        let mut webview = WebViewBuilder::new()
            .with_url(&url_str)
            .build(&window)
            .unwrap();

        event_loop.run(move |event, _, control_flow| {
            *control_flow = ControlFlow::Wait;

            if let tao::event::Event::Event::WindowEvent {
                event: tao::event::WindowEvent::CloseRequested,
                ..
            } = event
            {
                *control_flow = ControlFlow::Exit;
            }
        });
    }
}
