import QtQuick

// Liquid-glass body for the pill. `backdrop` is a texture of what's behind the
// pill, covering `target`'s parent (a live screen capture in the overlay).
// `mode`, `bLo` and `bHi` say how light it should be and how bright its
// surroundings are.
ShaderEffect {
    id: glass
    property Item backdrop: null
    property Item target: null
    property real pad: 28
    property real radius: height / 2
    property real band: 8
    property real strength: 1
    property real tilt: 0
    property point lightDir: Qt.point(Math.sin(-0.57 + tilt), -Math.cos(-0.57 + tilt))
    property color tintColor: "#343536"
    // Least tint each side ever gets; it goes heavier as needed for contrast.
    property real tintAlpha: 0.32
    property color lightColor: "#f5f5f7"
    property real lightAlpha: 0.55
    property vector4d tint: Qt.vector4d(tintColor.r, tintColor.g, tintColor.b, tintAlpha)
    property vector4d lightTint: Qt.vector4d(lightColor.r, lightColor.g, lightColor.b, lightAlpha)
    // 0 dark glass, 1 light glass (crossfades), and the darkest / brightest of
    // what's around the pill, 0 to 1.
    property real mode: 0
    property real bLo: 0.1
    property real bHi: 0.1
    property size size: Qt.size(width, height)
    visible: backdrop !== null
    // Where the pill sits on the screen the backdrop covers.
    property point origin: target ? Qt.point(target.x, target.y) : Qt.point(0, 0)
    property size screen: target && target.parent ? Qt.size(target.parent.width, target.parent.height)
                                                  : Qt.size(1, 1)
    property var backdropTex: glass.backdrop
    fragmentShader: Qt.resolvedUrl("shaders/glass.frag.qsb")
}
