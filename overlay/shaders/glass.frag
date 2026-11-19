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
    vec4 tint;
    vec4 lightTint;
    float lo;
    float hi;
};
layout(binding = 1) uniform sampler2D backdropTex;
layout(binding = 2) uniform sampler2D lumTex;

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
    // Soften it a little so the rim and the blurred middle meet without a seam.
    vec3 col = vec3(0.0);
    for (int i = -2; i <= 2; i++) {
        for (int j = 0; j <= 1; j++) {
            vec2 o = tng * float(i) * 1.8 + n * float(j) * 2.0;
            col += vec3(tap(sp + o + ca).r, tap(sp + o).g, tap(sp + o - ca).b);
        }
    }
    col /= 10.0;
    float a = pow(1.0 - t, 1.4) * 0.9 * inside;

    // A faint dark line right on the edge for separation, and glints where the
    // rounded ends face the light.
    float lip = exp(-depth / 0.8);
    float dark = lip * 0.30 * inside;
    vec2 L = normalize(lightDir);
    float glint = lip * inside * (0.55 * pow(max(dot(n, L), 0.0), 10.0)
                                + 0.30 * pow(max(dot(n, -L), 0.0), 10.0));

    // Dark glass over dark content, light glass over bright content, blended by
    // a smoothed brightness reading so it never snaps. Mid-tones get the most
    // tint, where light labels and dark labels both struggle.
    float lum = texture(lumTex, vec2(0.5)).r;
    float k = smoothstep(lo, hi, lum);
    vec3 tc = mix(tint.rgb, lightTint.rgb, k);
    float mid = 1.0 - abs(2.0 * clamp((lum - lo) / (hi - lo), 0.0, 1.0) - 1.0);
    float ta = (mix(tint.a, lightTint.a, k) + 0.14 * mid) * inside;
    dark *= 1.0 - 0.6 * k;
    vec3 rgb = col * a * (1.0 - dark);
    float alpha = a + dark * (1.0 - a);
    rgb = rgb * (1.0 - ta) + tc * ta;
    alpha = alpha + ta * (1.0 - alpha);
    rgb += vec3(glint);
    alpha = min(1.0, alpha + glint);
    fragColor = vec4(rgb, alpha) * strength * qt_Opacity;
}
