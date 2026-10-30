#version 460 core
#include <flutter/runtime_effect.glsl>

// A patterned wallpaper in one pass: the colour fill and the pattern over it,
// blended per pixel. Drawing the fill and then blending the pattern onto it
// needs an offscreen layer (the blend reads what is under it); computing both
// here needs none, so every frame costs one draw whether the fill is moving,
// the box is resizing or a route is sliding it.
//
// All positions are in the box's local logical pixels.

// Box size.
uniform vec2 u_size;

// Local position -> fill raster uv, as rows of a 2x3 affine map.
uniform vec3 u_fill_u;
uniform vec3 u_fill_v;

// Local position -> pattern raster uv.
uniform vec3 u_pattern_u;
uniform vec3 u_pattern_v;

// 0: the fill rasters (u_base, then u_overlay at u_overlay_opacity);
// 1: a linear gradient from u_color0 at u_from to u_color1 at u_to;
// 2: u_color0 flat.
uniform float u_fill_kind;
uniform float u_overlay_opacity;
uniform vec4 u_color0;
uniform vec4 u_color1;
uniform vec2 u_from;
uniform vec2 u_to;

// 0: soft light of u_ink over the fill; 1: the fill masked onto black.
uniform float u_blend;
// The pattern's intensity as an opacity, and how far its fade-in has come.
uniform float u_opacity;
uniform float u_strength;
// Soft-light ink: 0 black (over a light fill), 1 white (over a dark one).
uniform float u_ink;

uniform sampler2D u_base;
uniform sampler2D u_overlay;
uniform sampler2D u_pattern;

out vec4 frag_color;

vec2 mapped(vec2 p, vec3 u, vec3 v) {
  return vec2(dot(u, vec3(p, 1.0)), dot(v, vec3(p, 1.0)));
}

vec3 fill(vec2 p) {
  if (u_fill_kind < 0.5) {
    vec2 uv = mapped(p, u_fill_u, u_fill_v);
    vec3 base = texture(u_base, uv).rgb;
    vec3 overlay = texture(u_overlay, uv).rgb;
    return mix(base, overlay, u_overlay_opacity);
  }
  if (u_fill_kind < 1.5) {
    vec2 axis = u_to - u_from;
    float t = clamp(dot(p - u_from, axis) / dot(axis, axis), 0.0, 1.0);
    return mix(u_color0.rgb, u_color1.rgb, t);
  }
  return u_color0.rgb;
}

// W3C soft light of a black or white source over the destination d.
vec3 softLight(vec3 d) {
  if (u_ink < 0.5) return d * d;
  vec3 low = ((16.0 * d - 12.0) * d + 4.0) * d;
  return mix(sqrt(d), low, step(d, vec3(0.25)));
}

void main() {
  vec2 p = FlutterFragCoord().xy;
  vec3 d = fill(p);
  vec2 puv = mapped(p, u_pattern_u, u_pattern_v);
  // Cover-fit always spans the box; clamping only guards the last texel.
  float a = texture(u_pattern, clamp(puv, 0.0, 1.0)).a;
  vec3 c;
  if (u_blend < 0.5) {
    c = mix(d, softLight(d), u_opacity * u_strength * a);
  } else {
    // Black atop the fill where the pattern is not: the fill keeps
    // opacity x alpha of itself at full strength, all of itself at zero.
    c = d * (1.0 - u_strength * (1.0 - u_opacity * a));
  }
  frag_color = vec4(c, 1.0);
}
