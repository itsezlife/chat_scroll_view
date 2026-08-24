#version 460 core
#include <flutter/runtime_effect.glsl>

// Port of Telegram Android `liquid_glass_shader.agsl`.
// ImageFilter.shader auto-binds u_size (float 0..1) and u_texture (sampler 0).
//
// Pipeline (matches blur3 glass source): blur(+sat) first, then this shader.
// u_texture is already the frosted backdrop — do not blur after refraction.

uniform vec2 u_size;
uniform vec2 u_center;
uniform vec2 u_half_size;
// order: rightBottom, rightTop, leftBottom, leftTop (matches AGSL)
uniform vec4 u_radius;
uniform float u_thickness;
uniform float u_refract_index;
uniform float u_refract_intensity;
uniform vec4 u_foreground_premul;
// ColorMatrix.setSaturation(3) on the glass source (RenderNodeEffects).
uniform float u_saturation;

uniform sampler2D u_texture;

out vec4 frag_color;

float sdfRect(vec2 p, vec4 r) {
  r.xy = (p.x > 0.0) ? r.xy : r.zw;
  r.x = (p.y > 0.0) ? r.x : r.y;
  vec2 q = abs(p) - u_half_size + r.x;
  return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r.x;
}

vec4 srcOver(vec4 src, vec4 dst) {
  vec3 out_rgb = src.rgb + dst.rgb * (1.0 - src.a);
  float out_a = src.a + (1.0 - src.a) * dst.a;
  return vec4(out_rgb, out_a);
}

vec4 sampleBackdrop(vec2 pixel) {
  vec2 uv = pixel / u_size;
#ifdef IMPELLER_TARGET_OPENGLES
  uv.y = 1.0 - uv.y;
#endif
  return texture(u_texture, uv);
}

// Android ColorMatrix.setSaturation(s) luminance weights.
vec3 applySaturation(vec3 rgb, float s) {
  float luma = dot(rgb, vec3(0.213, 0.715, 0.072));
  return mix(vec3(luma), rgb, s);
}

void main() {
  vec2 frag_coord = FlutterFragCoord().xy;
  vec2 p = frag_coord - u_center;
  float sd = sdfRect(p, u_radius);
  vec2 sample_px = frag_coord;

  if (sd < 0.0) {
    float sd_x = sdfRect(p + vec2(1.0, 0.0), u_radius);
    float sd_y = sdfRect(p + vec2(0.0, 1.0), u_radius);

    float n_cos = max(u_thickness + sd, 0.0) / u_thickness;
    float n_cos2 = n_cos * n_cos;
    float n_sin = sqrt(max(1.0 - n_cos2, 0.0));
    vec3 normal = normalize(vec3((sd_x - sd) * n_cos, (sd_y - sd) * n_cos, n_sin));

    vec3 refract_vec = refract(vec3(0.0, 0.0, -1.0), normal, 1.0 / u_refract_index);
    float h = sd < -u_thickness
        ? u_thickness
        : sqrt(max(sd * (-2.0 * u_thickness - sd), 0.0));
    float refract_length = (h + 8.0 * u_thickness) / max(-refract_vec.z, 0.0001);

    sample_px += refract_vec.xy * refract_length * u_refract_intensity;
  }

  vec4 backdrop = sampleBackdrop(sample_px);
  backdrop.rgb = applySaturation(backdrop.rgb, u_saturation);
  frag_color = srcOver(u_foreground_premul, backdrop);
}
