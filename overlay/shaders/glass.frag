#version 440
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 size;
    vec2 origin;
    vec2 screen;
    float radius;
    float band;
    float strength;
    vec2 lightDir;
    vec4 tint;
    vec4 lightTint;
    float mode;
    float bLo;
    float bHi;
};
layout(binding = 1) uniform sampler2D backdropTex;

float box(vec2 p, vec2 b, float r) {
    vec2 q = abs(p) - b + r;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

vec3 tap(vec2 p) {
    return texture(backdropTex, (origin + size * 0.5 + p) / screen).rgb;
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

    // Edge: a crisp bright line all the way round (brighter where it faces the
    // light, with a weaker bounce opposite), sitting on a faint dark line.
    float lip = exp(-depth / 0.8);
    float line = smoothstep(1.6, 0.4, depth) * inside;
    vec2 L = normalize(lightDir);
    float face = dot(n, L);
    float rim = line * (0.16 + 0.42 * pow(max(face, 0.0), 3.0) + 0.22 * pow(max(-face, 0.0), 3.0));
    float dark = smoothstep(3.2, 1.4, depth) * (1.0 - line) * inside * 0.22;

    // Tint so labels always keep their contrast. Dark glass sizes itself
    // against the brightest things around the pill so white labels stay
    // readable over a bright patch; light glass sizes itself against the darkest
    // so dark labels do. mode crossfades between the two.
    float Ld = dot(tint.rgb, vec3(0.2126, 0.7152, 0.0722));
    float Ll = dot(lightTint.rgb, vec3(0.2126, 0.7152, 0.0722));
    float darkA = clamp((bHi - 0.26) / max(bHi - Ld, 1e-3), tint.a, 0.86);
    float lightA = clamp((0.84 - bLo) / max(Ll - bLo, 1e-3), lightTint.a, 0.9);
    vec3 tc = mix(tint.rgb, lightTint.rgb, mode);
    float ta = mix(darkA, lightA, mode) * inside;
    dark *= 1.0 - 0.7 * mode;

    vec3 rgb = col * a * (1.0 - dark);
    float alpha = a + dark * (1.0 - a);
    rgb = rgb * (1.0 - ta) + tc * ta;
    alpha = alpha + ta * (1.0 - alpha);
    rgb = rgb + vec3(rim) * (1.0 - rgb);
    alpha = min(1.0, alpha + rim * (1.0 - alpha));
    fragColor = vec4(rgb, alpha) * strength * qt_Opacity;
}
