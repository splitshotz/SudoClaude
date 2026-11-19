#version 440
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 size;
    float pad;
    float radius;
    float band;
    float strength;
    vec2 lightDir;
};
layout(binding = 1) uniform sampler2D backdropTex;

float box(vec2 p, vec2 b, float r) {
    vec2 q = abs(p) - b + r;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

vec3 tap(vec2 p) {
    return texture(backdropTex, (p + size * 0.5 + pad) / (size + 2.0 * pad)).rgb;
}

void main() {
    vec2 h = size * 0.5;
    vec2 p = qt_TexCoord0 * size - h;
    float d = box(p, h, radius);
    vec2 e = vec2(0.75, 0.0);
    vec2 n = vec2(box(p + e.xy, h, radius) - box(p - e.xy, h, radius),
                  box(p + e.yx, h, radius) - box(p - e.yx, h, radius));
    n /= max(length(n), 1e-4);
    vec2 tng = vec2(-n.y, n.x);
    float inside = smoothstep(0.75, -0.75, d);
    float depth = max(-d, 0.0);

    // Lens lip: inside the band you see what lies just past the edge, pulled in
    // and squeezed, the way a thick rounded rim bends light. Only pixels outside
    // the pill are ever read, so the pill never samples itself.
    float t = clamp(depth / band, 0.0, 1.0);
    float bend = pow(1.0 - t, 2.2);
    vec2 edge = p + n * depth;
    vec2 sp = edge + n * (1.5 + 15.0 * bend);
    vec2 ca = n * (0.6 + 2.2 * bend);
    vec3 col = vec3(0.0);
    for (int i = -1; i <= 1; i++) {
        vec2 o = tng * float(i) * 1.6;
        col += vec3(tap(sp + o + ca).r, tap(sp + o).g, tap(sp + o - ca).b);
    }
    col /= 3.0;
    float a = smoothstep(1.0, 0.0, t) * 0.92 * inside;

    // A faint dark line right on the edge for separation, and glints where the
    // rounded ends face the light.
    float lip = exp(-depth / 0.8);
    float dark = lip * 0.30 * inside;
    vec2 L = normalize(lightDir);
    float glint = lip * inside * (0.55 * pow(max(dot(n, L), 0.0), 10.0)
                                + 0.30 * pow(max(dot(n, -L), 0.0), 10.0));

    vec3 rgb = col * a * (1.0 - dark);
    float alpha = a + dark * (1.0 - a);
    rgb += vec3(glint);
    alpha = min(1.0, alpha + glint);
    fragColor = vec4(rgb, alpha) * strength * qt_Opacity;
}
