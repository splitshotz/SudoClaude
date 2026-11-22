import QtQuick
import "."

// Liquid glass behind `target`, refracting a texture of the content under it
// (`source`, normally the app's content layer; never anything that contains the
// glass itself). Same shader as the desktop pill.
ShaderEffect {
    id: glass
    property Item target: parent
    property Item source: Theme.backdrop
    property Item sourceSpace: Theme.scene
    property real radius: 24
    property real band: 10
    property real margin: 18
    property real frost: Theme.frost
    property real lens: Theme.lens
    property real tintMix: Theme.tintMix
    property color tintColor: "#2B2925"
    property color lightColor: "#FBF9F4"
    property real mode: Theme.mode
    Behavior on mode { NumberAnimation { duration: 400; easing.type: Easing.InOutQuad } }
    property real surround: Theme.surround
    Behavior on surround { NumberAnimation { duration: 450 } }
    property real strength: 1
    property real tilt: 0

    x: -margin
    y: -margin
    width: target ? target.width + 2 * margin : 0
    height: target ? target.height + 2 * margin : 0

    property size size: target ? Qt.size(target.width, target.height) : Qt.size(1, 1)
    property point origin: {
        Theme.tick
        if (!target || !sourceSpace) return Qt.point(0, 0)
        return target.mapToItem(sourceSpace, 0, 0)
    }
    property size screen: sourceSpace ? Qt.size(sourceSpace.width, sourceSpace.height) : Qt.size(1, 1)
    property point lightDir: Qt.point(Math.sin(-0.57 + tilt), -Math.cos(-0.57 + tilt))
    property vector4d tint: Qt.vector4d(tintColor.r, tintColor.g, tintColor.b, 1)
    property vector4d lightTint: Qt.vector4d(lightColor.r, lightColor.g, lightColor.b, 1)
    property real hasBackdrop: source ? 1 : 0
    property var backdropTex: source
    fragmentShader: Qt.resolvedUrl("shaders/glass.frag.qsb")
}
