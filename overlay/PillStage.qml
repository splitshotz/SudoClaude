import QtQuick

// The pill lives on a full-screen stage so it can sit anywhere. Drag it, or
// just throw it toward an edge or corner: on release it springs to whichever
// of the eight spots its momentum points at.
Item {
    id: stage

    property alias pill: pill
    property bool on: false
    property bool capturing: false
    property string at: "bottom"
    property real margin: 22
    property Item backdrop: null
    // Brightness around the pill; readings come in a couple of times a second and
    // this eases between them so the glass never snaps from dark to light.
    property real lum: 0.1
    Behavior on lum { NumberAnimation { duration: 550; easing.type: Easing.InOutQuad } }
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
                stage.tilt = Math.max(-0.9, Math.min(0.9, vx * 0.35))
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
        lum: stage.lum
        onStopRequested: stage.stopRequested()
        onTyped: t => stage.typed(t)
        opacity: stage.capturing ? 0 : fade
        property real fade: stage.on ? 1 : 0
        Behavior on fade { NumberAnimation { duration: stage.on ? 220 : 260; easing.type: Easing.OutCubic } }
        transformOrigin: stage.fy === 0 ? Item.Top : stage.fy === 1 ? Item.Bottom
                         : stage.fx === 0 ? Item.Left : Item.Right
        scale: !stage.on ? 0.86 : grab.moving ? 1.04 : 1
        Behavior on scale { SpringAnimation { spring: 5; damping: 0.38; epsilon: 0.002 } }
        transform: Translate {
            x: stage.on ? 0 : (stage.fy === 0.5 ? (stage.fx === 0 ? -18 : 18) : 0)
            y: stage.on ? 0 : (stage.fy === 0 ? -18 : stage.fy === 1 ? 18 : 0)
            Behavior on x { SpringAnimation { spring: 4.5; damping: 0.42 } }
            Behavior on y { SpringAnimation { spring: 4.5; damping: 0.42 } }
        }
    }
}
