#version 440
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 size;        // the pill
    float margin;     // room around it for the shadow
    vec2 origin;      // pill's top-left on the screen the backdrop covers
    vec2 screen;
    float radius;
    float band;       // width of the refracting lip
    float frost;      // blur radius in px
    float strength;
    vec2 lightDir;
    vec4 tint;        // dark glass
    vec4 lightTint;   // light glass
    float mode;       // 0 dark, 1 light
    float hasBackdrop;
    float surround;   // average brightness around the pill
    float lens;       // refraction strength, 1 = default
    float tintMix;    // how much of the glass's own tint shows, 0.12 default
};
layout(binding = 1) uniform sampler2D backdropTex;

float box(vec2 p, vec2 b, float r) {
    vec2 q = abs(p) - b + r;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

vec3 tap(vec2 p) {
    return texture(backdropTex, (origin + size * 0.5 + p) / screen).rgb;
}

// Light frost: a 16-tap spiral, no noise.
vec3 frosted(vec2 p) {
    vec3 acc = tap(p);
    for (int i = 0; i < 16; i++) {
        float a = float(i) * 2.39996;
        float r = frost * sqrt((float(i) + 0.5) / 16.0);
        acc += tap(p + vec2(cos(a), sin(a)) * r);
    }
    return acc / 17.0;
}

float luma(vec3 c) { return dot(c, vec3(0.2126, 0.7152, 0.0722)); }

// Compress everything above `knee` so it eases toward `ceil` but never passes it.
float cap(float x, float knee, float ceil_) {
    if (x <= knee) return x;
    float r = ceil_ - knee;
    return knee + r * (1.0 - exp(-(x - knee) / r));
}

void main() {
    vec2 h = size * 0.5;
    vec2 p = qt_TexCoord0 * (size + 2.0 * margin) - h - margin;
    float d = box(p, h, radius);
    vec2 e = vec2(0.75, 0.0);
    vec2 n = vec2(box(p + e.xy, h, radius) - box(p - e.xy, h, radius),
                  box(p + e.yx, h, radius) - box(p - e.yx, h, radius));
    n /= max(length(n), 1e-4);
    float inside = smoothstep(0.75, -0.75, d);
    float depth = max(-d, 0.0);

    // Soft shadow under the glass, kept faint so the compositor never blurs it.
    float sh = box(p - vec2(0.0, 3.0), h, radius);
    float shadow = 0.13 * exp(-max(sh, 0.0) / 7.0) * (1.0 - inside);

    vec3 rgb;
    float alpha;
    if (hasBackdrop > 0.5) {
        // Lens: at the lip you see what's just past the edge, pulled in; the
        // middle is magnified a touch, like a thick convex slab.
        float t = clamp(depth / band, 0.0, 1.0);
        float bend = pow(1.0 - t, 2.0);
        vec2 q = p * (1.0 - 0.05 * lens) + n * (16.0 * lens * bend);
        vec2 ca = n * (0.4 + 1.6 * bend) * lens;
        vec3 c = vec3(frosted(q + ca).r, frosted(q).g, frosted(q - ca).b);

        // Color comes through stronger and brightness is remapped into a
        // narrow band that always sits apart from the surroundings: dark glass a
        // step lighter than what's around it, light glass a step darker, so the
        // pill reads as a piece of glass on the page and labels keep contrast.
        // The content's own light and shade still show inside that band.
        float L = luma(c);
        c = clamp(mix(vec3(L), c, 1.2), 0.0, 1.0);
        L = luma(c);
        float dLo = clamp(surround + 0.07, 0.10, 0.18);
        float dHi = dLo + 0.2;
        float lHi = clamp(surround - 0.08, 0.80, 0.90);
        float lLo = lHi - 0.2;
        float Ld = dLo + (dHi - dLo) * L;
        float Ll = lLo + (lHi - lLo) * L;
        // Shift brightness rather than scale it, so color keeps its real
        // strength instead of being blown up on dark content.
        float Lt = mix(Ld, Ll, mode);
        c = clamp(c + (Lt - L), 0.0, 1.0);
        // A whisper of the glass's own tint ties it to the shell's palette.
        c = mix(c, mix(tint.rgb, lightTint.rgb, mode), tintMix);
        rgb = c * inside;
        alpha = inside;
    } else {
        // No backdrop (fullscreen apps): translucent tint over the compositor's blur.
        vec3 tc = mix(tint.rgb, lightTint.rgb, mode);
        float ta = mix(0.62, 0.72, mode) * inside;
        rgb = tc * ta;
        alpha = ta;
    }

    // Edge: a crisp bright line all the way round, brighter where it faces the
    // light, over a faint dark line.
    float line = smoothstep(1.6, 0.4, depth) * inside;
    vec2 L2 = normalize(lightDir);
    float face = dot(n, L2);
    float rim = line * (0.18 + 0.45 * pow(max(face, 0.0), 3.0) + 0.25 * pow(max(-face, 0.0), 3.0));
    float dark = smoothstep(3.2, 1.4, depth) * (1.0 - line) * inside * 0.20 * (1.0 - 0.7 * mode);
    rgb *= 1.0 - dark;
    rgb = rgb + vec3(rim) * (1.0 - rgb);
    alpha = min(1.0, alpha + rim * (1.0 - alpha));

    // Shadow goes under everything else.
    rgb = rgb + vec3(0.0) * shadow * (1.0 - alpha);
    alpha = alpha + shadow * (1.0 - alpha);
    fragColor = vec4(rgb, alpha) * strength * qt_Opacity;
}
