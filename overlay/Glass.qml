import QtQuick

// Liquid glass for the pill. `backdrop` is a texture of what's really behind
// the pill (wallpaper plus live window captures, never the overlay itself),
// covering `target`'s parent. Without one it falls back to a tint over the
// compositor's blur.
ShaderEffect {
    id: glass
    property Item backdrop: null
    property Item target: null
    property real margin: 18
    property real radius: target ? target.height / 2 : 24
    property real band: 10
    property real frost: 5
    property real strength: 1
    property real tilt: 0
    property point lightDir: Qt.point(Math.sin(-0.57 + tilt), -Math.cos(-0.57 + tilt))
    property color tintColor: "#343536"
    property color lightColor: "#f5f5f7"
    property vector4d tint: Qt.vector4d(tintColor.r, tintColor.g, tintColor.b, 1)
    property vector4d lightTint: Qt.vector4d(lightColor.r, lightColor.g, lightColor.b, 1)
    // 0 dark glass, 1 light glass; crossfades.
    property real mode: 0
    property real hasBackdrop: backdrop ? 1 : 0

    x: target ? -margin : 0
    y: target ? -margin : 0
    width: target ? target.width + 2 * margin : 0
    height: target ? target.height + 2 * margin : 0
    property size size: target ? Qt.size(target.width, target.height) : Qt.size(1, 1)
    property point origin: target ? Qt.point(target.x, target.y) : Qt.point(0, 0)
    property size screen: target && target.parent ? Qt.size(target.parent.width, target.parent.height)
                                                  : Qt.size(1, 1)
    property var backdropTex: backdrop ? backdrop : blank
    fragmentShader: Qt.resolvedUrl("shaders/glass.frag.qsb")

    // Something to bind when there's no backdrop; the shader doesn't read it then.
    Rectangle { id: blankSrc; width: 1; height: 1; color: "black" }
    ShaderEffectSource { id: blank; width: 0; height: 0; sourceItem: blankSrc; hideSource: true }
}
