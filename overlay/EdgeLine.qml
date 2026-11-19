import QtQuick

ShaderEffect {
    id: fx
    property real intensity: 0
    property real rx: 0
    property real ry: 0
    property real rw: width
    property real rh: height
    property real el: 1
    property real er: 1
    property real et: 1
    property real eb: 1
    property real radius: 0
    property bool travelling: true
    property bool outside: false
    property real level: 0
    property real lapSeconds: 14

    visible: intensity > 0.003
    property real time: 0
    property real comet: travelling ? 1 : 0
    Behavior on comet { NumberAnimation { duration: 900; easing.type: Easing.InOutSine } }
    property real lap: lapSeconds
    property real outward: outside ? 1 : 0
    property size size: Qt.size(width, height)
    property rect rect: Qt.rect(rx, ry, rw, rh)
    property vector4d edges: Qt.vector4d(el, er, et, eb)
    property vector4d colA: Qt.vector4d(0.851, 0.467, 0.341, 1)
    property vector4d colB: Qt.vector4d(0.985, 0.80, 0.67, 1)
    fragmentShader: "shaders/edge.frag.qsb"

    FrameAnimation {
        running: fx.visible
        onTriggered: fx.time += frameTime
    }
}
