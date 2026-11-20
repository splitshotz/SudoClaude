import QtQuick
import "."

// The liquid glass itself, drawn under `target`. It refracts the app's own
// background (Theme.backdrop), so it reads real content without ever sampling
// itself. Same shader as the desktop pill.
ShaderEffect {
    id: glass
    property Item target: parent
    property real radius: 24
    property real band: 10
    property real margin: 18
    property real frost: Theme.frost
    property real lens: Theme.lens
    property real tintMix: Theme.tintMix
    property color tintColor: Theme.dark ? "#2A2522" : "#FFFBF6"
    property color lightColor: Theme.dark ? "#2A2522" : "#FFFBF6"
    property real mode: Theme.mode
    property real surround: Theme.surround
    property real strength: 1
    property real tilt: 0

    x: -margin
    y: -margin
    width: target ? target.width + 2 * margin : 0
    height: target ? target.height + 2 * margin : 0

    property size size: target ? Qt.size(target.width, target.height) : Qt.size(1, 1)
    property point origin: {
        Theme.tick
        if (!target || !Theme.scene) return Qt.point(0, 0)
        return target.mapToItem(Theme.scene, 0, 0)
    }
    property size screen: Theme.scene ? Qt.size(Theme.scene.width, Theme.scene.height) : Qt.size(1, 1)
    property point lightDir: Qt.point(Math.sin(-0.57 + tilt), -Math.cos(-0.57 + tilt))
    property vector4d tint: Qt.vector4d(tintColor.r, tintColor.g, tintColor.b, 1)
    property vector4d lightTint: Qt.vector4d(lightColor.r, lightColor.g, lightColor.b, 1)
    property real hasBackdrop: Theme.backdrop ? 1 : 0
    property var backdropTex: Theme.backdrop
    fragmentShader: Qt.resolvedUrl("shaders/glass.frag.qsb")
}
