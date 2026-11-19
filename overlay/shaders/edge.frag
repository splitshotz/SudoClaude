#version 440
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float time;
    float intensity;
    float comet;
    float level;
    float radius;
    float lap;
    float outward;
    vec2 size;
    vec4 rect;
    vec4 edges;
    vec4 colA;
    vec4 colB;
};

// Hairline around a rounded rect, with a short bright comet that travels the
// perimeter. edges = (left, right, top, bottom) weights; a side-only line uses
// the same path with the other edges switched off.
void main() {
    vec2 px = qt_TexCoord0 * size;
    vec2 c = rect.xy + rect.zw * 0.5;
    vec2 h = rect.zw * 0.5;
    vec2 q = abs(px - c) - h + radius;
    float d = -(length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius);
    if (outward > 0.5) d = -d;

    // which edge we're nearest, for masking and the perimeter coordinate
    vec2 rel = px - rect.xy;
    float W = rect.z, H = rect.w;
    float dl = rel.x, dr = W - rel.x, dt = rel.y, db = H - rel.y;
    float m = min(min(dl, dr), min(dt, db));
    float s, w;
    if (m == dt)      { s = rel.x;                 w = edges.z; }
    else if (m == dr) { s = W + rel.y;             w = edges.y; }
    else if (m == db) { s = W + H + (W - rel.x);   w = edges.w; }
    else              { s = 2.0 * W + H + (H - rel.y); w = edges.x; }
    float perim = 2.0 * (W + H);

    float line = smoothstep(1.9, 0.6, abs(d - 1.0));
    float bloom = exp(-max(d, 0.0) / 12.0) * step(-0.5, d);

    float head = fract(time / lap) * perim;
    float behind = mod(head - s, perim);
    float tail = exp(-behind / 260.0) * comet;
    float ahead = mod(s - head, perim);
    tail += exp(-ahead / 18.0) * comet * 0.6;

    float lv = level * exp(-pow((s - (W + H + W * 0.5)) / (W * 0.18), 2.0));

    float a = (line * (0.55 + 0.9 * tail + 1.2 * lv) + bloom * (0.10 + 0.5 * tail + 0.6 * lv)) * w;
    a = clamp(a * intensity, 0.0, 1.0);
    vec3 col = mix(colA.rgb, colB.rgb, clamp(tail + lv, 0.0, 1.0) * 0.7);
    fragColor = vec4(col * a, a) * qt_Opacity;
}
