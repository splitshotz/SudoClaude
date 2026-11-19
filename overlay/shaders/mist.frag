#version 440
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float time;
    float spread;
    float intensity;
    float level;
    float halo;
    float radius;
    float seed;
    vec2 size;
    vec4 rect;
    vec4 edges;
    vec4 colA;
    vec4 colB;
    vec4 colC;
};

float hash(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
               mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
    float v = 0.0;
    float a = 0.5;
    mat2 m = mat2(1.6, 1.2, -1.2, 1.6);
    for (int i = 0; i < 5; i++) {
        v += a * noise(p);
        p = m * p;
        a *= 0.5;
    }
    return v;
}

void main() {
    vec2 px = qt_TexCoord0 * size;
    float m;
    if (halo < 0.5) {
        float s = spread * (1.0 + 0.45 * level);
        float dl = max(px.x - rect.x, 0.0);
        float dr = max(rect.x + rect.z - px.x, 0.0);
        float dt = max(px.y - rect.y, 0.0);
        float db = max(rect.y + rect.w - px.y, 0.0);
        m = edges.x * exp(-dl / s) + edges.y * exp(-dr / s)
          + edges.z * exp(-dt / s) + edges.w * exp(-db / s);
    } else {
        vec2 c = rect.xy + rect.zw * 0.5;
        vec2 q = abs(px - c) - rect.zw * 0.5 + radius;
        float d = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius;
        float s = spread * (1.0 + 0.45 * level);
        m = d > 0.0 ? exp(-d / s) : exp(d / (s * 0.35)) * 0.6;
    }

    vec2 uv = px / 260.0 + seed;
    float t = time * 0.045;
    vec2 w = vec2(fbm(uv + vec2(t, -t * 0.7)), fbm(uv + vec2(-t * 0.8, t) + 5.2));
    float n = fbm(uv * 1.25 + 2.4 * w + vec2(t * 0.6, t * 0.25));
    float wisps = smoothstep(0.28, 0.82, n);
    float a = m * (0.22 + 1.05 * wisps) * intensity;
    a = clamp(a, 0.0, 0.92);

    vec3 col = mix(colC.rgb, colA.rgb, smoothstep(0.15, 0.55, n));
    col = mix(col, colB.rgb, smoothstep(0.55, 0.95, n) * 0.85);
    fragColor = vec4(col * a, a) * qt_Opacity;
}
