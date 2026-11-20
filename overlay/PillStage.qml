import QtQuick

// The pill lives on a full-screen stage so it can sit anywhere. Drag it, or
// just throw it toward an edge or corner: on release it springs to whichever
// of the eight spots its momentum points at.
Item {
    id: stage

    property alias pill: pill
    property alias bubble: bubble
    property string replyText: ""
    property bool replyShown: false
    property bool on: false
    property bool capturing: false
    property string at: "bottom"
    property real margin: 22
    property Item backdrop: null
    // Brightness around the pill: readings arrive a couple of times a second as
    // "mean darkest brightest". The glass goes light past 0.6 and back to dark
    // under 0.45, so a mixed background doesn't make it flicker, and every
    // change eases instead of snapping.
    property real lum: 0.1
    Behavior on lum { NumberAnimation { duration: 450; easing.type: Easing.InOutQuad } }
    property real lumLo: 0.1
    property real lumHi: 0.1
    property bool lightGlass: false
    // "auto" follows what's behind the glass; "light" / "dark" pin it.
    property string appearance: "auto"
    property real frost: 5
    property real lens: 1
    property real tintMix: 0.12
    property real mode: appearance === "light" ? 1 : appearance === "dark" ? 0 : (lightGlass ? 1 : 0)
    Behavior on lumLo { NumberAnimation { duration: 450; easing.type: Easing.InOutQuad } }
    Behavior on lumHi { NumberAnimation { duration: 450; easing.type: Easing.InOutQuad } }
    Behavior on mode { NumberAnimation { duration: 380; easing.type: Easing.InOutQuad } }
    function reading(text) {
        const v = text.trim().split(/\s+/).map(parseFloat)
        if (v.length < 3 || v.some(isNaN)) return
        lum = v[0]; lumLo = v[1]; lumHi = v[2]
        if (!lightGlass && v[0] > 0.6) lightGlass = true
        else if (lightGlass && v[0] < 0.45) lightGlass = false
    }
    // Space taken by bars on each side: [left, top, right, bottom].
    property var insets: [0, 0, 0, 0]
    signal moved(string at)
    signal stopRequested()
    signal typed(string text)

    readonly property var spots: ["top-left", "top", "top-right", "left", "right",
                                  "bottom-left", "bottom", "bottom-right"]

    function spot(n) {
        const fx = n.indexOf("left") >= 0 ? 0 : n.indexOf("right") >= 0 ? 1 : 0.5
        const fy = n.indexOf("top") >= 0 ? 0 : n.indexOf("bottom") >= 0 ? 1 : 0.5
        const l = insets[0] + margin, t = insets[1] + margin
        const r = width - insets[2] - margin, b = height - insets[3] - margin
        return {
            x: fx === 0 ? l : fx === 1 ? r : (l + r) / 2,
            y: fy === 0 ? t : fy === 1 ? b : (t + b) / 2,
            fx: fx, fy: fy
        }
    }

    // Anchor point plus which part of the pill sits on it, so the pill grows
    // away from its edge as the transcript gets longer.
    property real px: width / 2
    property real py: height - margin
    property real fx: 0.5
    property real fy: 1
    property bool ready: false
    property real tilt: 0
    Behavior on tilt { SpringAnimation { spring: 2.6; damping: 0.25; epsilon: 0.002 } }
    // Drag velocity, normalised; the glass stretches along it like a droplet
    // and springs back round when let go.
    property real vxn: 0
    property real vyn: 0
    Behavior on vxn { SpringAnimation { spring: 3.4; damping: 0.22; epsilon: 0.002 } }
    Behavior on vyn { SpringAnimation { spring: 3.4; damping: 0.22; epsilon: 0.002 } }
    readonly property bool springy: ready && !grab.moving
    Behavior on px { enabled: stage.springy; SpringAnimation { spring: 3.2; damping: 0.3; epsilon: 0.25 } }
    Behavior on py { enabled: stage.springy; SpringAnimation { spring: 3.2; damping: 0.3; epsilon: 0.25 } }
    Behavior on fx { enabled: stage.springy; SpringAnimation { spring: 3.2; damping: 0.4; epsilon: 0.002 } }
    Behavior on fy { enabled: stage.springy; SpringAnimation { spring: 3.2; damping: 0.4; epsilon: 0.002 } }

    function settle() {
        const s = spot(spots.indexOf(at) >= 0 ? at : "bottom")
        px = s.x; py = s.y; fx = s.fx; fy = s.fy
    }
    // Geometry changes jump straight to the spot; only moves between spots spring.
    function snap() { const r = ready; ready = false; settle(); ready = r }
    onAtChanged: settle()
    onWidthChanged: snap()
    onHeightChanged: snap()
    onInsetsChanged: snap()
    onOnChanged: if (on && !grab.moving) snap()
    Component.onCompleted: { settle(); ready = true }

    // Hit area under the pill: only the stop button sits above it.
    MouseArea {
        id: grab
        x: pill.x; y: pill.y
        width: pill.width; height: pill.height
        enabled: stage.on && !pill.typing
        cursorShape: moving ? Qt.ClosedHandCursor : Qt.OpenHandCursor
        property bool moving: false
        property real ox: 0
        property real oy: 0
        property var trail: []

        onPressed: e => {
            const p = mapToItem(stage, e.x, e.y)
            ox = p.x - stage.px
            oy = p.y - stage.py
            trail = [{ x: p.x, y: p.y, t: Date.now() }]
            moving = false
        }
        onPositionChanged: e => {
            const p = mapToItem(stage, e.x, e.y)
            if (!moving && Math.hypot(p.x - trail[0].x, p.y - trail[0].y) < 5) return
            moving = true
            stage.px = p.x - ox
            stage.py = p.y - oy
            const now = Date.now()
            trail = trail.concat([{ x: p.x, y: p.y, t: now }]).filter(s => now - s.t < 90)
            if (trail.length > 1) {
                const a = trail[0], b = trail[trail.length - 1]
                const vx = (b.x - a.x) / Math.max(1, b.t - a.t)
                const vy = (b.y - a.y) / Math.max(1, b.t - a.t)
                stage.tilt = Math.max(-0.9, Math.min(0.9, vx * 0.35))
                stage.vxn = Math.max(-1, Math.min(1, vx / 2.2))
                stage.vyn = Math.max(-1, Math.min(1, vy / 2.2))
            }
        }
        onReleased: {
            if (!moving) return
            let vx = 0, vy = 0
            const a = trail[0], b = trail[trail.length - 1]
            if (trail.length > 1 && b.t > a.t && Date.now() - b.t < 60) {
                vx = (b.x - a.x) / (b.t - a.t) * 1000
                vy = (b.y - a.y) / (b.t - a.t) * 1000
            }
            // Where it would coast to, then the nearest spot to that.
            const w = pill.width, h = pill.height
            const cx = pill.x + w / 2 + vx * 0.28
            const cy = pill.y + h / 2 + vy * 0.28
            let best = stage.at, bd = 1e12
            for (const n of stage.spots) {
                const s = stage.spot(n)
                const d = Math.hypot(s.x - w * s.fx + w / 2 - cx, s.y - h * s.fy + h / 2 - cy)
                if (d < bd) { bd = d; best = n }
            }
            moving = false
            stage.tilt = 0
            stage.vxn = 0
            stage.vyn = 0
            if (best === stage.at) stage.settle()
            else stage.at = best
            stage.moved(best)
        }
    }

    Pill {
        id: pill
        x: Math.round(stage.px - width * stage.fx)
        y: Math.round(stage.py - height * stage.fy)
        lifted: grab.moving
        tilt: stage.tilt
        // Glass shows up by its lens growing in, not just a fade.
        appear: fade
        backdrop: stage.backdrop
        mode: stage.mode
        surround: stage.lum
        frost: stage.frost
        lens: stage.lens
        tintMix: stage.tintMix
        onStopRequested: stage.stopRequested()
        onTyped: t => stage.typed(t)
        opacity: stage.capturing ? 0 : fade
        property real fade: stage.on ? 1 : 0
        Behavior on fade {
            SpringAnimation { spring: stage.on ? 4.2 : 6; damping: stage.on ? 0.42 : 0.7; epsilon: 0.003 }
        }
        transformOrigin: stage.fy === 0 ? Item.Top : stage.fy === 1 ? Item.Bottom
                         : stage.fx === 0 ? Item.Left : Item.Right
        scale: !stage.on ? 0.86 : grab.moving ? 1.04 : 1
        Behavior on scale { SpringAnimation { spring: 5; damping: 0.38; epsilon: 0.002 } }
        transform: [
            Scale {
                origin.x: pill.width / 2
                origin.y: pill.height / 2
                xScale: 1 + 0.07 * Math.abs(stage.vxn) - 0.035 * Math.abs(stage.vyn)
                yScale: 1 + 0.10 * Math.abs(stage.vyn) - 0.05 * Math.abs(stage.vxn)
            },
            Translate {
                x: stage.on ? 0 : (stage.fy === 0.5 ? (stage.fx === 0 ? -18 : 18) : 0)
                y: stage.on ? 0 : (stage.fy === 0 ? -18 : stage.fy === 1 ? 18 : 0)
                Behavior on x { SpringAnimation { spring: 4.5; damping: 0.42 } }
                Behavior on y { SpringAnimation { spring: 4.5; damping: 0.42 } }
            }
        ]
    }

    // Typed replies: above the pill when it's at the bottom, below it at the
    // top, beside it on the sides, lined up with the pill's own edge.
    Bubble {
        id: bubble
        readonly property real gap: 12
        text: stage.replyText
        shown: stage.replyShown && stage.on
        backdrop: stage.backdrop
        mode: stage.mode
        surround: stage.lum
        tilt: stage.tilt
        frost: stage.frost + 1
        lens: stage.lens
        tintMix: stage.tintMix
        textColor: pill.blend(pill.fg, pill.accent, 0.12)
        fontFamily: pill.fontFamily
        maxTextWidth: Math.min(460, stage.width * 0.4)
        maxHeight: Math.min(320, stage.height * 0.4)
        origin: stage.fy === 1 ? Item.Bottom : stage.fy === 0 ? Item.Top
              : stage.fx === 0 ? Item.Left : Item.Right
        x: {
            const lo = stage.insets[0] + stage.margin
            const hi = stage.width - stage.insets[2] - stage.margin - width
            if (stage.fy === 0.5)
                return stage.fx === 0 ? pill.x + pill.width + gap : pill.x - width - gap
            const want = pill.x + pill.width * stage.fx - width * stage.fx
            return Math.max(lo, Math.min(hi, want))
        }
        y: {
            if (stage.fy === 1) return pill.y - height - gap
            if (stage.fy === 0) return pill.y + pill.height + gap
            const lo = stage.insets[1] + stage.margin
            const hi = stage.height - stage.insets[3] - stage.margin - height
            return Math.max(lo, Math.min(hi, pill.y + pill.height / 2 - height / 2))
        }
    }
}
