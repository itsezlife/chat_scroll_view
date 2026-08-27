#version 460 core
#include <flutter/runtime_effect.glsl>

// Approximates Telegram glass `DownscaledRenderNode` scale N× at full
// resolution: box-average an N×N neighborhood before Gaussian blur.
// ImageFilter.shader auto-binds u_size + u_texture.

uniform vec2 u_size;
// Source downscale (typically 4). Values outside 2..8 clamp in the shader.
uniform float u_scale;

uniform sampler2D u_texture;

out vec4 frag_color;

vec4 sampleAt(vec2 pixel) {
  vec2 uv = pixel / u_size;
#ifdef IMPELLER_TARGET_OPENGLES
  uv.y = 1.0 - uv.y;
#endif
  return texture(u_texture, uv);
}

void main() {
  vec2 p = FlutterFragCoord().xy;
  // Unrolled 4×4 (Telegram default). If u_scale != 4, still use 4×4 span
  // sized by u_scale so effective footprint matches downscale.
  float n = clamp(u_scale, 2.0, 8.0);
  float origin = -(n - 1.0) * 0.5;
  vec4 c = vec4(0.0);
  for (int y = 0; y < 4; y++) {
    for (int x = 0; x < 4; x++) {
      // Map 0..3 taps across the N×N footprint (even when N != 4).
      float fx = origin + (float(x) + 0.5) * (n / 4.0);
      float fy = origin + (float(y) + 0.5) * (n / 4.0);
      c += sampleAt(p + vec2(fx, fy));
    }
  }
  frag_color = c * 0.0625; // 1/16
}
