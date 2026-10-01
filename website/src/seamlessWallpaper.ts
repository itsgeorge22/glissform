// Bundled wallpaper only. This is the original projection and blur shader,
// now drawn to a texture inside the MacBook scene’s WebGL context.
export const desktopFragmentSource = `#version 300 es
precision highp float;
uniform sampler2D desktop;
uniform float fold;
uniform vec2 imageSize;
uniform vec4 projection;
uniform vec4 shading;
in vec2 screenUV;
out vec4 outputColor;

void main() {
  if (fold < 0.0001) {
    outputColor = texture(desktop, screenUV);
    return;
  }
  // Match ScreenProjection's seated viewpoint and softly bounded image angle.
  float heightFromHinge = 1.0 - screenUV.y;
  float depth = heightFromHinge * projection.x;
  float planeHeight = heightFromHinge * projection.y;
  float rayScale = 4.0 / (4.0 - depth);
  float visibleWidth = mix(1.0, projection.z, heightFromHinge);
  vec2 uv = vec2(0.5 + (screenUV.x - 0.5) / visibleWidth,
                 1.0 - (1.1 + (planeHeight - 1.1) * rayScale));

  float verticalBlur = smoothstep(0.0, 1.0, heightFromHinge);
  float radius = shading.x * mix(0.015, 0.090, verticalBlur) * mix(0.70, 0.80, verticalBlur);
  float lod = 0.5 * log2(1.0 + 0.25 * radius * radius);
  vec2 stepSize = radius * 0.5 / imageSize;
  float weights[5] = float[5](0.0625, 0.25, 0.375, 0.25, 0.0625);
  vec3 color = vec3(0.0);
  for (int y = 0; y < 5; y++) {
    for (int x = 0; x < 5; x++) {
      vec2 offset = vec2(float(x - 2), float(y - 2)) * stepSize;
      color += pow(textureLod(desktop, uv + offset, lod).rgb, vec3(2.2)) * weights[x] * weights[y];
    }
  }
  vec2 feather = max(vec2(radius * 1.1547) / imageSize, vec2(0.5) / imageSize);
  vec2 entering = smoothstep(-feather, feather, uv);
  vec2 leaving = 1.0 - smoothstep(1.0 - feather, 1.0 + feather, uv);
  color *= entering.x * entering.y * leaving.x * leaving.y;
  float broadShadow = shading.y * (1.0 - smoothstep(0.05, 1.0, screenUV.y));
  float contactShadow = shading.z * exp(-pow(screenUV.y / shading.w, 1.6));
  color *= (1.0 - broadShadow) * (1.0 - contactShadow);
  outputColor = vec4(pow(color, vec3(1.0 / 2.2)), 1.0);
}`;
