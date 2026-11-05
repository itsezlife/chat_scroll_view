//! What a file uses that tlottie does not render. Informational only: a file
//! that uses these still loads, and the host decides what to do about it.

use serde_json::Value;

pub const LAYER_EFFECTS: u32 = 1;
pub const EXPRESSIONS: u32 = 2;
pub const IMAGES: u32 = 4;
pub const TEXT: u32 = 8;

const LAYER_TYPE_IMAGE: u64 = 2;
const LAYER_TYPE_TEXT: u64 = 5;

/// Bitmask of unrendered features in `json`; `0` when the scan cannot run
/// (serde_json refuses nesting past its own recursion limit, and a scan
/// failure must never fail a load tlottie already accepted).
pub fn scan(json: &[u8]) -> u32 {
    match serde_json::from_slice::<Value>(json) {
        Ok(root) => scan_root(&root),
        Err(_) => 0,
    }
}

fn scan_root(root: &Value) -> u32 {
    let mut found = scan_layers(root.get("layers"));
    if let Some(assets) = root.get("assets").and_then(Value::as_array) {
        for asset in assets {
            found |= scan_layers(asset.get("layers"));
            // A precomp carries layers; an asset with a file reference is an image.
            if asset.get("layers").is_none() && asset.get("p").is_some_and(Value::is_string) {
                found |= IMAGES;
            }
        }
    }
    found | expressions_in(root)
}

fn scan_layers(layers: Option<&Value>) -> u32 {
    let mut found = 0;
    for layer in layers.and_then(Value::as_array).into_iter().flatten() {
        if layer.get("ef").and_then(Value::as_array).is_some_and(|e| !e.is_empty()) {
            found |= LAYER_EFFECTS;
        }
        match layer.get("ty").and_then(Value::as_u64) {
            Some(LAYER_TYPE_IMAGE) => found |= IMAGES,
            Some(LAYER_TYPE_TEXT) => found |= TEXT,
            _ => {}
        }
    }
    found
}

/// An expression is a string under `x` on a property. Split position also
/// uses `x`, but as an object, so only a string counts.
fn expressions_in(value: &Value) -> u32 {
    let hit = match value {
        Value::Object(map) => {
            if map.get("x").is_some_and(Value::is_string) {
                return EXPRESSIONS;
            }
            map.values().any(|v| expressions_in(v) != 0)
        }
        Value::Array(items) => items.iter().any(|v| expressions_in(v) != 0),
        _ => false,
    };
    if hit {
        EXPRESSIONS
    } else {
        0
    }
}
