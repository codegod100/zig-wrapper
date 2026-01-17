use std::ffi::CStr;
use std::os::raw::c_char;
use std::sync::Mutex;
use once_cell::sync::Lazy;

pub type IpcCallback = extern "C" fn(*const c_char);

struct UnsafeSync<T>(T);
unsafe impl<T> Sync for UnsafeSync<T> {}
unsafe impl<T> Send for UnsafeSync<T> {}

static WEBVIEW: Lazy<Mutex<Option<UnsafeSync<wry::WebView>>>> = Lazy::new(|| Mutex::new(None));

#[no_mangle]
pub extern "C" fn wry_create_and_run(url: *const c_char) {
    wry_create_and_run_with_ipc(url, None);
}

#[no_mangle]
pub extern "C" fn wry_eval(js: *const c_char) {
    if js.is_null() { return; }
    let js_str = unsafe { CStr::from_ptr(js).to_string_lossy().into_owned() };
    
    if let Ok(guard) = WEBVIEW.lock() {
        if let Some(wrapper) = guard.as_ref() {
            let _ = wrapper.0.evaluate_script(&js_str);
        }
    }
}

#[no_mangle]
pub extern "C" fn wry_create_and_run_with_ipc(url: *const c_char, callback: Option<IpcCallback>) {
    #[cfg(target_os = "linux")]
    if std::env::var("DISPLAY").is_err() && std::env::var("WAYLAND_DISPLAY").is_err() {
        eprintln!("[ERROR] No display available");
        return;
    }

    let url_str = unsafe {
        if url.is_null() {
            String::from("https://www.example.com")
        } else {
            CStr::from_ptr(url).to_string_lossy().into_owned()
        }
    };
    
    // Check if it's HTML content (heuristic)
    let is_html = url_str.trim_start().starts_with("<!DOCTYPE") || url_str.trim_start().starts_with("<html");

    use wry::WebViewBuilder;
    use tao::event_loop::{ControlFlow, EventLoop};
    use tao::window::WindowBuilder;

    let event_loop = EventLoop::new();
    let window = WindowBuilder::new()
        .with_title("File Browser")
        .build(&event_loop)
        .unwrap();

    let mut webview_builder = if is_html {
        WebViewBuilder::new().with_html(&url_str)
    } else {
        WebViewBuilder::new().with_url(&url_str)
    };
    webview_builder = webview_builder.with_devtools(true);

    if let Some(cb) = callback {
        webview_builder = webview_builder.with_ipc_handler(move |msg| {
            let body = msg.body();
            let c_msg = std::ffi::CString::new(body.as_str()).unwrap();
            cb(c_msg.as_ptr());
        });
    }

    #[cfg(not(any(target_os = "windows", target_os = "macos", target_os = "ios", target_os = "android")))]
    let webview = {
        use tao::platform::unix::WindowExtUnix;
        use wry::WebViewBuilderExtUnix;
        let vbox = window.default_vbox().unwrap();
        webview_builder.build_gtk(vbox).unwrap()
    };

    #[cfg(any(target_os = "windows", target_os = "macos", target_os = "ios", target_os = "android"))]
    let webview = webview_builder.build(&window).unwrap();

    *WEBVIEW.lock().unwrap() = Some(UnsafeSync(webview));

    event_loop.run(move |event, _, control_flow| {
        *control_flow = ControlFlow::Wait;
        if let tao::event::Event::WindowEvent { event, .. } = event {
            match event {
                tao::event::WindowEvent::CloseRequested => {
                    *control_flow = ControlFlow::Exit;
                }
                tao::event::WindowEvent::MouseInput {
                    state: tao::event::ElementState::Pressed,
                    button: tao::event::MouseButton::Right,
                    ..
                } => {
                    #[cfg(any(debug_assertions, feature = "devtools"))]
                    if let Ok(guard) = WEBVIEW.lock() {
                        if let Some(wrapper) = guard.as_ref() {
                            wrapper.0.open_devtools();
                        }
                    }
                }
                _ => {}
            }
        }
    });
}
