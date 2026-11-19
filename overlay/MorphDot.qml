import QtQuick
import QtQuick.Shapes

// A small shape that keeps morphing between soft multi-lobed forms, in the
// spirit of Material 3 Expressive's loading indicator. While listening it
// turns into a wavy circle that swells with the voice level.
Item {
    id: dot
    property color color: "#D97757"
    property bool listening: false
    property bool busy: true
    property bool stopped: false
    property real level: 0
    property real size: 22

    width: size
    height: size

    property real t: 0
    property real lobes: listening ? 9 : 5
    Behavior on lobes { SpringAnimation { spring: 3; damping: 0.5 } }
    property real amp: stopped ? 0 : listening ? 0.05 + 0.16 * level : busy ? 0.13 : 0.06
    Behavior on amp { SpringAnimation { spring: 4; damping: 0.45 } }
    property real grow: listening ? 0.86 + 0.24 * level : 0.92
    Behavior on grow { SpringAnimation { spring: 5; damping: 0.4 } }

    FrameAnimation {
        running: dot.visible && !dot.stopped
        onTriggered: dot.t += frameTime
    }

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        rotation: dot.t * (dot.listening ? 40 : 70)
        ShapePath {
            strokeColor: "transparent"
            fillColor: dot.stopped ? "#8C817C" : dot.color
            PathPolyline {
                path: {
                    const n = 56, pts = []
                    const R = dot.size / 2 * dot.grow * 0.92
                    const c = dot.size / 2
                    const wob = Math.sin(dot.t * 1.7) * 0.5 + 0.5
                    for (let i = 0; i <= n; i++) {
                        const a = i / n * Math.PI * 2
                        const r = R * (1 - dot.amp * 0.5 + dot.amp * (0.5 + 0.5 * Math.cos(dot.lobes * a + wob)))
                        pts.push(Qt.point(c + r * Math.cos(a), c + r * Math.sin(a)))
                    }
                    return pts
                }
            }
        }
    }
}
