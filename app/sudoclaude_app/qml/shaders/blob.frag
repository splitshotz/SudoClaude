#version 440
// Material Expressive's soft shapes (cookies, clovers, flowers): a circle whose
// radius ripples with `lobes`, anti-aliased with the SDF's screen-space slope.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec4 color;
    float lobes;
    float depth;   // how deep the ripples go, 0..0.3
    float spin;    // radians
    float px;      // one pixel in uv units
};
void main() {
    vec2 p = qt_TexCoord0 * 2.0 - 1.0;
    float r = length(p);
    float a = atan(p.y, p.x) + spin;
    float edge = 1.0 - depth + depth * (0.5 + 0.5 * cos(a * lobes));
    float d = r - edge * 0.98;
    float aa = px * 2.4;
    float k = 1.0 - smoothstep(-aa, aa, d);
    fragColor = vec4(color.rgb * color.a, color.a) * k * qt_Opacity;
}
