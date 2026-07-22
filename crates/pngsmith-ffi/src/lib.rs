use std::{
    ffi::{CStr, CString, c_char},
    panic::{AssertUnwindSafe, catch_unwind},
};

#[unsafe(no_mangle)]
/// Executes a UTF-8 JSON request and returns an owned UTF-8 JSON response.
///
/// # Safety
///
/// `request` must be null or point to a valid NUL-terminated byte string for
/// the duration of this call. The returned pointer must be released exactly
/// once with [`pngsmith_string_free`].
pub unsafe extern "C" fn pngsmith_execute_json(request: *const c_char) -> *mut c_char {
    if request.is_null() {
        return json_error("request was null");
    }
    let result = catch_unwind(AssertUnwindSafe(|| {
        let request = unsafe { CStr::from_ptr(request) }
            .to_str()
            .map_err(|e| e.to_string())?;
        pngsmith_core::execute_json(request).map_err(|e| e.to_string())
    }));
    match result {
        Ok(Ok(response)) => into_c_string(response),
        Ok(Err(error)) => json_error(&error),
        Err(_) => json_error("Rust compression engine panicked"),
    }
}

#[unsafe(no_mangle)]
/// Releases a response returned by [`pngsmith_execute_json`].
///
/// # Safety
///
/// `pointer` must be null or a pointer returned by `pngsmith_execute_json`
/// that has not previously been freed.
pub unsafe extern "C" fn pngsmith_string_free(pointer: *mut c_char) {
    if !pointer.is_null() {
        unsafe {
            drop(CString::from_raw(pointer));
        }
    }
}

fn into_c_string(value: String) -> *mut c_char {
    CString::new(value)
        .unwrap_or_else(|_| {
            CString::new(r#"{"ok":false,"error":"invalid response","results":[]}"#).unwrap()
        })
        .into_raw()
}

fn json_error(message: &str) -> *mut c_char {
    into_c_string(serde_json::json!({ "ok": false, "error": message, "results": [] }).to_string())
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn null_request_is_a_json_error() {
        let result = unsafe { pngsmith_execute_json(std::ptr::null()) };
        let value = unsafe { CStr::from_ptr(result) }
            .to_str()
            .unwrap()
            .to_owned();
        unsafe {
            pngsmith_string_free(result);
        }
        assert!(value.contains("request was null"));
    }
}
