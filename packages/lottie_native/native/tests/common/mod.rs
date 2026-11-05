//! Hand-authored fixtures and a safe-ish wrapper over the C ABI for the tests.
#![allow(dead_code)]

use chat_lottie::{chat_lottie_free, chat_lottie_load, ChatLottie, ChatLottieInfo};
use std::io::Write;

/// A 100x100, 30 fps, 60 frame animation: one rotating 60x60 square filled
/// with 50% opaque orange. `layer_extra` is spliced into the shape layer,
/// `opacity_extra` into its opacity property, `extra_layers` and `assets`
/// are appended to the matching arrays.
pub fn fixture_with(
    layer_extra: &str,
    opacity_extra: &str,
    extra_layers: &str,
    assets: &str,
) -> String {
    format!(
        r#"{{"v":"5.5.2","fr":30,"ip":0,"op":60,"w":100,"h":100,"nm":"fixture","ddd":0,
"assets":[{assets}],
"layers":[{{"ddd":0,"ind":1,"ty":4,"nm":"square","sr":1{layer_extra},
"ks":{{"o":{{"a":0,"k":100{opacity_extra}}},
"r":{{"a":1,"k":[{{"t":0,"s":[0],"i":{{"x":[0.5],"y":[1]}},"o":{{"x":[0.5],"y":[0]}}}},{{"t":60,"s":[90]}}]}},
"p":{{"a":0,"k":[50,50,0]}},"a":{{"a":0,"k":[0,0,0]}},"s":{{"a":0,"k":[100,100,100]}}}},
"ao":0,
"shapes":[{{"ty":"gr","it":[
{{"ty":"rc","d":1,"s":{{"a":0,"k":[60,60]}},"p":{{"a":0,"k":[0,0]}},"r":{{"a":0,"k":0}}}},
{{"ty":"fl","c":{{"a":0,"k":[1,0.5,0.25,1]}},"o":{{"a":0,"k":50}},"r":1}},
{{"ty":"tr","p":{{"a":0,"k":[0,0]}},"a":{{"a":0,"k":[0,0]}},"s":{{"a":0,"k":[100,100]}},"r":{{"a":0,"k":0}},"o":{{"a":0,"k":100}}}}
]}}],"ip":0,"op":60,"st":0,"bm":0}}{extra_layers}]}}"#
    )
}

pub fn fixture() -> String {
    fixture_with("", "", "", "")
}

pub fn gzip(bytes: &[u8]) -> Vec<u8> {
    let mut enc = flate2::write::GzEncoder::new(Vec::new(), flate2::Compression::fast());
    enc.write_all(bytes).unwrap();
    enc.finish().unwrap()
}

/// An owned handle that frees itself, so a failing assert does not leak.
pub struct Loaded {
    pub handle: *mut ChatLottie,
    pub info: ChatLottieInfo,
}

impl Drop for Loaded {
    fn drop(&mut self) {
        unsafe { chat_lottie_free(self.handle) };
    }
}

// A handle is used by one thread at a time; moving it between threads is the
// documented use.
unsafe impl Send for Loaded {}

pub fn try_load(bytes: &[u8]) -> Result<Loaded, i32> {
    let mut info = ChatLottieInfo::default();
    let mut handle = std::ptr::null_mut();
    let status = unsafe { chat_lottie_load(bytes.as_ptr(), bytes.len(), &mut info, &mut handle) };
    if status == 0 {
        assert!(!handle.is_null(), "status 0 must come with a handle");
        Ok(Loaded { handle, info })
    } else {
        assert!(handle.is_null(), "a failed load must leave the handle null");
        Err(status)
    }
}

pub fn load(bytes: &[u8]) -> Loaded {
    try_load(bytes).unwrap_or_else(|status| panic!("load failed with {status}"))
}
