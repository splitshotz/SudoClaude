#version 440
// Material 3 Expressive's wavy progress line: the moving active stretch is a sine
// wave, the rest a flatLine track, with a gap between them.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 size;
    float phase;     // wave travel
    float head;      // 0..1 where the active stretch ends
    float len;       // its length, 0..1
    vec4 activeColor;
    vec4 track;
};
float seg(float x, float a, float b) { return step(a, x) * step(x, b); }
void main() {
    vec2 p = qt_TexCoord0 * size;
    float cy = size.y * 0.5;
    float amp = 3.0, k = 6.2831 / 38.0, th = 2.6;
    float x0 = (head - len) * size.x, x1 = head * size.x;
    float y = cy + amp * sin(p.x * k - phase);
    float slope = amp * k * cos(p.x * k - phase);
    float d = abs(p.y - y) / sqrt(1.0 + slope * slope);
    float wave = (1.0 - smoothstep(th - 1.0, th + 0.5, d)) * smoothstep(x0 - 0.5, x0 + 1.5, p.x) * (1.0 - smoothstep(x1 - 1.5, x1 + 0.5, p.x));
    float gap = 8.0;
    float flatLine = 1.0 - smoothstep(th - 1.0, th + 0.5, abs(p.y - cy));
    float outside = 1.0 - smoothstep(x0 - gap - 1.0, x0 - gap, p.x) * (1.0 - smoothstep(x1 + gap, x1 + gap + 1.0, p.x));
    flatLine *= outside;
    vec4 c = activeColor * wave + track * flatLine * (1.0 - wave);
    fragColor = vec4(c.rgb * c.a, c.a) * qt_Opacity;
}
