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

float hash(float n) { return fract(sin(n) * 43758.5453); }

float noise(float x) {
    float i = floor(x);
    float f = fract(x);
    float u = f * f * (3.0 - 2.0 * f);
    return mix(hash(i + seed * 17.0), hash(i + 1.0 + seed * 17.0), u);
}

// Slow, smooth swelling along an edge: two octaves drifting in opposite
// directions so the light seems to breathe and travel rather than pulse.
float swell(float p, float t) {
    return 0.62 * noise(p / 420.0 + t * 0.11) + 0.38 * noise(p / 190.0 - t * 0.17 + 7.3);
}

vec2 glow(float d, float p, float t, float s) {
    float n = swell(p, t);
    float width = s * (0.7 + 0.7 * n) * (1.0 + 0.5 * level);
    float soft = exp(-d / width);
    float core = exp(-d / 2.2);
    float a = soft * (0.55 + 0.6 * n) + core * (0.35 + 0.45 * n);
    return vec2(a, n);
}

void main() {
    vec2 px = qt_TexCoord0 * size;
    float t = time;
    vec2 g = vec2(0.0);

    if (halo < 0.5) {
        float dl = max(px.x - rect.x, 0.0);
        float dr = max(rect.x + rect.z - px.x, 0.0);
        float dt = max(px.y - rect.y, 0.0);
        float db = max(rect.y + rect.w - px.y, 0.0);
        vec2 e;
        e = glow(dl, px.y, t, spread);          g += edges.x * e;
        e = glow(dr, px.y + 911.0, t, spread);  g += edges.y * e;
        e = glow(dt, px.x + 377.0, t, spread);  g += edges.z * e;
        e = glow(db, px.x + 1531.0, t, spread); g += edges.w * e;
        g.y = clamp(g.y, 0.0, 1.0);
    } else {
        vec2 c = rect.xy + rect.zw * 0.5;
        vec2 q = abs(px - c) - rect.zw * 0.5 + radius;
        float d = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius;
        g = glow(max(d, 0.0), px.x + px.y, t, spread);
        g.x *= d < 0.0 ? exp(d / 3.0) : 1.0;
    }

    float a = clamp(g.x * 0.6 * intensity, 0.0, 0.8);
    vec3 col = mix(colC.rgb, colA.rgb, 0.65 + 0.35 * g.y);
    col = mix(col, colB.rgb, smoothstep(0.6, 1.0, g.y) * 0.5);
    fragColor = vec4(col * a, a) * qt_Opacity;
}
