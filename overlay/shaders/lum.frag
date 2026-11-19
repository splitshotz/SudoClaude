#version 440
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 size;
    float pad;
    float rate;
};
layout(binding = 1) uniform sampler2D backdropTex;
layout(binding = 2) uniform sampler2D prevTex;

// Average brightness of a ring just outside the pill, eased toward over time
// (this output feeds back in as prevTex), so the glass changes smoothly.
void main() {
    vec2 full = size + 2.0 * pad;
    float lum = 0.0;
    vec2 e = size * 0.5 + pad * 0.55;
    for (int k = 0; k < 7; k++) {
        float x = mix(-e.x, e.x, (float(k) + 0.5) / 7.0);
        lum += dot(texture(backdropTex, (vec2(x, -e.y) + full * 0.5) / full).rgb, vec3(0.2126, 0.7152, 0.0722));
        lum += dot(texture(backdropTex, (vec2(x, e.y) + full * 0.5) / full).rgb, vec3(0.2126, 0.7152, 0.0722));
    }
    lum += dot(texture(backdropTex, (vec2(-e.x, 0.0) + full * 0.5) / full).rgb, vec3(0.2126, 0.7152, 0.0722));
    lum += dot(texture(backdropTex, (vec2(e.x, 0.0) + full * 0.5) / full).rgb, vec3(0.2126, 0.7152, 0.0722));
    lum /= 16.0;
    float prev = texture(prevTex, vec2(0.5)).r;
    float v = mix(prev, lum, rate);
    fragColor = vec4(v, v, v, 1.0);
}
