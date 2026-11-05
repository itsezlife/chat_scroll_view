mod common;
use common::*;

const EFFECTS: u32 = 1;
const EXPRESSIONS: u32 = 2;
const IMAGES: u32 = 4;
const TEXT: u32 = 8;

fn features_of(json: String) -> u32 {
    load(json.as_bytes()).info.features
}

#[test]
fn effect_is_flagged_and_the_file_still_loads() {
    let json = fixture_with(r#","ef":[{"ty":5,"nm":"Blur","en":1,"ef":[]}]"#, "", "", "");
    assert_eq!(features_of(json), EFFECTS);
}

#[test]
fn expression_string_is_flagged() {
    let json = fixture_with("", r#","x":"time * 20""#, "", "");
    assert_eq!(features_of(json), EXPRESSIONS);
}

#[test]
fn text_layer_is_flagged() {
    let text = r#",{"ddd":0,"ind":2,"ty":5,"nm":"t","ks":{},"ip":0,"op":60,"st":0,"t":{}}"#;
    assert_eq!(features_of(fixture_with("", "", text, "")), TEXT);
}

#[test]
fn image_layer_and_image_asset_are_flagged() {
    let layer = r#",{"ddd":0,"ind":2,"ty":2,"nm":"i","refId":"img_0","ks":{},"ip":0,"op":60,"st":0}"#;
    assert_eq!(features_of(fixture_with("", "", layer, "")), IMAGES);
    let asset = r#"{"id":"img_0","w":4,"h":4,"u":"","p":"data:image/png;base64,AAAA","e":1}"#;
    assert_eq!(features_of(fixture_with("", "", "", asset)), IMAGES);
}

#[test]
fn features_combine() {
    let text = r#",{"ddd":0,"ind":2,"ty":5,"nm":"t","ks":{},"ip":0,"op":60,"st":0,"t":{}}"#;
    let json = fixture_with(r#","ef":[{"ty":5}]"#, r#","x":"wiggle(1,2)""#, text, "");
    assert_eq!(features_of(json), EFFECTS | EXPRESSIONS | TEXT);
}

#[test]
fn split_position_is_not_an_expression() {
    // Lottie's split-position property is an object under "x"; only a string is an expression.
    let json = fixture().replace(
        r#""p":{"a":0,"k":[50,50,0]}"#,
        r#""p":{"s":true,"x":{"a":0,"k":50},"y":{"a":0,"k":50}}"#,
    );
    assert_eq!(features_of(json), 0);
}
