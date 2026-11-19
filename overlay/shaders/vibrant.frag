#version 440
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float lo;
    float hi;
};
layout(binding = 1) uniform sampler2D source;
layout(binding = 2) uniform sampler2D lumTex;

// Labels on the glass follow it: neutral colors invert their lightness as the
// glass turns light, saturated ones (the orange dot) are left alone.
void main() {
    vec4 s = texture(source, qt_TexCoord0);
    float k = smoothstep(lo, hi, texture(lumTex, vec2(0.5)).r);
    vec3 c = s.a > 0.0 ? s.rgb / s.a : vec3(0.0);
    float mx = max(c.r, max(c.g, c.b)), mn = min(c.r, min(c.g, c.b));
    float neutral = 1.0 - smoothstep(0.10, 0.22, mx - mn);
    float L = dot(c, vec3(0.2126, 0.7152, 0.0722));
    vec3 flipped = clamp(c + (1.0 - 1.08 * L) - L, 0.0, 1.0);
    c = mix(c, flipped, k * neutral);
    fragColor = vec4(c * s.a, s.a) * qt_Opacity;
}
