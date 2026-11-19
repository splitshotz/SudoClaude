#version 440
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 size;
    float radius;
    float strength;
};

float box(vec2 p, vec2 b, float r) {
    vec2 q = abs(p) - b + r;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

void main() {
    vec2 half_ = size * 0.5;
    vec2 p = qt_TexCoord0 * size - half_;
    float d = box(p, half_, radius);
    vec2 e = vec2(0.75, 0.0);
    vec2 n = vec2(box(p + e.xy, half_, radius) - box(p - e.xy, half_, radius),
                  box(p + e.yx, half_, radius) - box(p - e.yx, half_, radius));
    n /= max(length(n), 1e-4);
    float inside = smoothstep(0.6, -0.6, d);
    float depth = max(-d, 0.0);
    // Light comes from above and a little to the left; the far edge catches a
    // weaker bounce, the way a curved glass lip does.
    float facing = dot(n, normalize(vec2(-0.35, -1.0)));
    float lit = pow(max(facing, 0.0), 1.6);
    float bounce = pow(max(-facing, 0.0), 2.0);
    float rim = exp(-depth / 1.3);
    float lens = exp(-depth / 6.5);
    float a = rim * (0.10 + 0.62 * lit + 0.28 * bounce) + lens * (0.11 * lit + 0.05 * bounce);
    a *= inside * strength * qt_Opacity;
    fragColor = vec4(a, a, a, a);
}
