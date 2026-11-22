package io.github.splitshotz.sudoclaude.phone;

import android.animation.Animator;
import android.animation.AnimatorListenerAdapter;
import android.animation.ValueAnimator;
import android.content.Context;
import android.graphics.Canvas;
import android.graphics.LinearGradient;
import android.graphics.Paint;
import android.graphics.Path;
import android.graphics.RectF;
import android.graphics.Shader;
import android.graphics.Typeface;
import android.os.Build;
import android.view.Display;
import android.view.RoundedCorner;
import android.view.View;
import android.view.animation.DecelerateInterpolator;
import android.view.animation.PathInterpolator;

/** The same look as the desktop overlay: Claude-orange edge glow and Claude's cursor. */
public class OverlayView extends View {
    private static final int ACCENT = 0xFFD97757;
    private static final int ACCENT_HI = 0xFFEBA286;

    private final float dp;
    private final Paint edge = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint fill = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint stroke = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint shadow = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint chip = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint text = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint ripple = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Path arrow = new Path();
    private final RectF rect = new RectF();

    private float glow;          // edge visibility 0..1
    private float cx = -1, cy = -1;
    private float cursorAlpha;
    private float press = 1f;    // cursor scale while pressing
    private float rippleT = 1f;  // 0..1, 1 = done
    private float rippleX, rippleY;
    private float breathe;
    private String label = "";
    private float corner;

    private ValueAnimator glowAnim, moveAnim, rippleAnim, pressAnim, breatheAnim;

    public OverlayView(Context c) {
        super(c);
        dp = c.getResources().getDisplayMetrics().density;
        edge.setStyle(Paint.Style.STROKE);
        edge.setColor(ACCENT);
        stroke.setStyle(Paint.Style.STROKE);
        stroke.setColor(0xFFFFFFFF);
        stroke.setStrokeWidth(1.8f);
        stroke.setStrokeJoin(Paint.Join.ROUND);
        shadow.setStyle(Paint.Style.FILL);
        shadow.setColor(0x661F0D05);
        chip.setColor(ACCENT);
        text.setColor(0xFFFFFFFF);
        text.setTextSize(12.5f * dp);
        text.setTypeface(Typeface.create("sans-serif-medium", Typeface.NORMAL));
        ripple.setStyle(Paint.Style.STROKE);
        ripple.setColor(ACCENT);
        ripple.setStrokeWidth(2.5f * dp);

        arrow.moveTo(4.5f, 3.5f);
        arrow.lineTo(7.6f, 20.2f);
        arrow.quadTo(8.3f, 20.9f, 9.4f, 19.9f);
        arrow.lineTo(11.6f, 15.6f);
        arrow.lineTo(18.4f, 14.9f);
        arrow.quadTo(19.8f, 14.3f, 18.9f, 13.2f);
        arrow.lineTo(6.2f, 3.0f);
        arrow.quadTo(4.9f, 2.3f, 4.5f, 3.5f);
        arrow.close();
        fill.setShader(new LinearGradient(4, 3, 16, 19, ACCENT_HI, ACCENT, Shader.TileMode.CLAMP));
        corner = 24 * dp;
    }

    @Override
    protected void onAttachedToWindow() {
        super.onAttachedToWindow();
        if (Build.VERSION.SDK_INT >= 31) {
            Display d = getDisplay();
            RoundedCorner rc = d != null ? d.getRoundedCorner(RoundedCorner.POSITION_TOP_LEFT) : null;
            if (rc != null && rc.getRadius() > 0) corner = rc.getRadius();
        }
        breatheAnim = ValueAnimator.ofFloat(0f, 1f);
        breatheAnim.setDuration(2600);
        breatheAnim.setRepeatMode(ValueAnimator.REVERSE);
        breatheAnim.setRepeatCount(ValueAnimator.INFINITE);
        breatheAnim.addUpdateListener(a -> {
            breathe = (float) a.getAnimatedValue();
            invalidate();
        });
        breatheAnim.start();
    }

    @Override
    protected void onDetachedFromWindow() {
        if (breatheAnim != null) breatheAnim.cancel();
        super.onDetachedFromWindow();
    }

    // ---- commands --------------------------------------------------------------
    public void show(String l) {
        if (l != null) label = l;
        fadeGlow(1f, null);
    }

    public void hide(Runnable done) {
        fadeGlow(0f, done);
    }

    public void peek(boolean hidden) {
        setVisibility(hidden ? INVISIBLE : VISIBLE);
    }

    public void tap(int x, int y, String l, int holdMs) {
        label = l;
        fadeGlow(1f, null);
        moveTo(x, y, 220, () -> {
            pressCursor(holdMs);
            startRipple(x, y);
        });
    }

    public void swipe(int x, int y, int x2, int y2, int ms, String l) {
        label = l;
        fadeGlow(1f, null);
        moveTo(x, y, 160, () -> {
            pressCursor(0);
            moveTo(x2, y2, Math.max(120, ms), null);
        });
    }

    // ---- animation -------------------------------------------------------------
    private void fadeGlow(float to, Runnable done) {
        if (glowAnim != null) glowAnim.cancel();
        glowAnim = ValueAnimator.ofFloat(glow, to);
        glowAnim.setDuration(to > glow ? 320 : 420);
        glowAnim.setInterpolator(new DecelerateInterpolator());
        glowAnim.addUpdateListener(a -> {
            glow = (float) a.getAnimatedValue();
            if (to < 0.5f) cursorAlpha = Math.min(cursorAlpha, glow);
            invalidate();
        });
        if (done != null) {
            glowAnim.addListener(new AnimatorListenerAdapter() {
                boolean cancelled;

                @Override
                public void onAnimationCancel(Animator a) {
                    cancelled = true;
                }

                @Override
                public void onAnimationEnd(Animator a) {
                    if (!cancelled) done.run();
                }
            });
        }
        glowAnim.start();
    }

    private void moveTo(float x, float y, long ms, Runnable then) {
        if (moveAnim != null) moveAnim.cancel();
        if (cx < 0) {  // first appearance: start just below the target and rise in
            cx = x;
            cy = y + 60 * dp;
        }
        final float sx = cx, sy = cy, a0 = cursorAlpha;
        moveAnim = ValueAnimator.ofFloat(0f, 1f);
        moveAnim.setDuration(ms);
        moveAnim.setInterpolator(new PathInterpolator(0.2f, 0f, 0f, 1f));
        moveAnim.addUpdateListener(a -> {
            float t = (float) a.getAnimatedValue();
            cx = sx + (x - sx) * t;
            cy = sy + (y - sy) * t;
            cursorAlpha = a0 + (1f - a0) * Math.min(1f, t * 2);
            invalidate();
        });
        if (then != null) {
            moveAnim.addListener(new AnimatorListenerAdapter() {
                boolean cancelled;

                @Override
                public void onAnimationCancel(Animator a) {
                    cancelled = true;
                }

                @Override
                public void onAnimationEnd(Animator a) {
                    if (!cancelled) then.run();
                }
            });
        }
        moveAnim.start();
    }

    private void pressCursor(int holdMs) {
        if (pressAnim != null) pressAnim.cancel();
        pressAnim = ValueAnimator.ofFloat(0f, 1f);
        pressAnim.setDuration(330 + holdMs);
        final float down = 70f / (330 + holdMs), hold = (70f + holdMs) / (330 + holdMs);
        pressAnim.addUpdateListener(a -> {
            float t = (float) a.getAnimatedValue();
            if (t < down) press = 1f - 0.18f * (t / down);
            else if (t < hold) press = 0.82f;
            else {
                float u = (t - hold) / (1f - hold);
                // overshoot back to full size
                float s = 2.2f;
                float v = u - 1f;
                press = 0.82f + 0.18f * (v * v * ((s + 1) * v + s) + 1f);
            }
            invalidate();
        });
        pressAnim.start();
    }

    private void startRipple(float x, float y) {
        rippleX = x;
        rippleY = y;
        if (rippleAnim != null) rippleAnim.cancel();
        rippleAnim = ValueAnimator.ofFloat(0f, 1f);
        rippleAnim.setDuration(520);
        rippleAnim.setInterpolator(new DecelerateInterpolator(1.6f));
        rippleAnim.addUpdateListener(a -> {
            rippleT = (float) a.getAnimatedValue();
            invalidate();
        });
        rippleAnim.start();
    }

    // ---- drawing ---------------------------------------------------------------
    @Override
    protected void onDraw(Canvas c) {
        int w = getWidth(), h = getHeight();
        if (glow > 0.001f) {
            float b = 0.85f + 0.15f * breathe;
            // soft glow: wide faint strokes inside, a crisp line at the edge
            float[] widths = {28, 18, 11, 6, 2.5f};
            int[] alphas = {14, 24, 40, 70, 200};
            for (int i = 0; i < widths.length; i++) {
                float sw = widths[i] * dp;
                edge.setStrokeWidth(sw);
                edge.setAlpha((int) (alphas[i] * glow * b));
                rect.set(sw / 2, sw / 2, w - sw / 2, h - sw / 2);
                float r = Math.max(0, corner - sw / 2);
                c.drawRoundRect(rect, r, r, edge);
            }
        }
        if (rippleT < 1f && glow > 0.01f) {
            ripple.setAlpha((int) (200 * (1f - rippleT) * glow));
            c.drawCircle(rippleX, rippleY, (8 + 30 * rippleT) * dp, ripple);
        }
        if (cx >= 0 && cursorAlpha > 0.01f) {
            float s = 1.35f * dp * press;
            c.save();
            c.translate(cx - 4.5f * s, cy - 3.2f * s);
            c.scale(s, s);
            int al = (int) (255 * cursorAlpha);
            c.save();
            c.translate(0.6f, 1.4f);
            shadow.setAlpha((int) (0.4f * al));
            c.drawPath(arrow, shadow);
            c.restore();
            fill.setAlpha(al);
            stroke.setAlpha(al);
            c.drawPath(arrow, fill);
            c.drawPath(arrow, stroke);
            c.restore();

            if (label != null && !label.isEmpty()) {
                String t = "Claude  " + label;
                float tw = text.measureText(t);
                float px = cx + 18 * dp, py = cy + 20 * dp;
                float ph = 22 * dp, pw = tw + 18 * dp;
                if (px + pw > w - 8 * dp) px = cx - pw - 6 * dp;
                if (py + ph > h - 8 * dp) py = cy - ph - 6 * dp;
                chip.setAlpha((int) (235 * cursorAlpha));
                rect.set(px, py, px + pw, py + ph);
                c.drawRoundRect(rect, ph / 2, ph / 2, chip);
                text.setAlpha(al);
                c.drawText(t, px + 9 * dp, py + ph / 2 - (text.ascent() + text.descent()) / 2, text);
            }
        }
    }
}
