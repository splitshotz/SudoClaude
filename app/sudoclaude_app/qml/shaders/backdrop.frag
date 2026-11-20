#version 440
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 size;
    float time;
    float dark;
    float hue;       // drifts the light a little between setup steps
    vec4 c1;         // base
    vec4 c2;         // base, other corner
    vec4 c3;         // the orange light
};

// Calm warm base (charcoal or paper) with soft, blurred orange light drifting
// through it: a couple of slow diagonal beams and a low glow. No noise.
float beam(vec2 p, vec2 dir, float off, float width) {
    float d = dot(p, normalize(dir)) - off;
    return exp(-d * d / (width * width));
}

void main() {
    vec2 uv = qt_TexCoord0;
    float aspect = size.x / max(size.y, 1.0);
    vec2 p = vec2(uv.x * aspect, uv.y);
    float t = time * 0.05;

    vec3 col = mix(c1.rgb, c2.rgb, smoothstep(-0.2, 1.2, uv.x * 0.6 + uv.y * 0.7));

    float light = 0.0;
    light += 0.60 * beam(p, vec2(1.0, 0.62), aspect * 0.62 + 0.18 * sin(t * 0.8) + hue * 0.25, 0.26);
    light += 0.35 * beam(p, vec2(1.0, 0.40), aspect * 0.30 + 0.22 * cos(t * 0.6 + 1.0) - hue * 0.15, 0.16);
    vec2 g = uv - vec2(0.72 - hue * 0.2, 0.95);
    light += 0.75 * exp(-dot(g * vec2(1.0, 1.6), g * vec2(1.0, 1.6)) * 3.2);
    vec2 g2 = uv - vec2(0.12 + hue * 0.1, 0.05);
    light += 0.35 * exp(-dot(g2, g2) * 5.0);

    float amount = clamp(light, 0.0, 1.0) * mix(0.55, 0.34, dark);
    col = mix(col, c3.rgb, amount);

    vec2 v = uv - 0.5;
    col *= 1.0 - mix(0.04, 0.20, dark) * dot(v, v) * 2.0;
    fragColor = vec4(clamp(col, 0.0, 1.0), 1.0) * qt_Opacity;
}
