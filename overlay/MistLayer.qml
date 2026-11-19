import QtQuick

Item {
    id: mist

    property real intensity: 0
    property real level: 0
    property bool halo: false
    property real rx: 0
    property real ry: 0
    property real rw: width
    property real rh: height
    property real el: 1
    property real er: 1
    property real et: 1
    property real eb: 1
    property real spread: 110
    property real radius: 18
    property real seed: 0
    property real downscale: 3
    property bool frozen: false

    visible: intensity > 0.003
    layer.enabled: visible
    layer.smooth: true
    layer.textureSize: Qt.size(Math.max(1, Math.round(width / downscale)),
                               Math.max(1, Math.round(height / downscale)))

    ShaderEffect {
        id: fx
        anchors.fill: parent
        property real time: 0
        property real spread: mist.spread
        property real intensity: Math.min(1.4, mist.intensity)
        property real level: mist.level
        property real halo: mist.halo ? 1 : 0
        property real radius: mist.radius
        property real seed: mist.seed
        property size size: Qt.size(width, height)
        property rect rect: Qt.rect(mist.rx, mist.ry, mist.rw, mist.rh)
        property vector4d edges: Qt.vector4d(mist.el, mist.er, mist.et, mist.eb)
        property vector4d colA: Qt.vector4d(0.851, 0.467, 0.341, 1)
        property vector4d colB: Qt.vector4d(0.985, 0.80, 0.67, 1)
        property vector4d colC: Qt.vector4d(0.70, 0.29, 0.25, 1)
        fragmentShader: "shaders/mist.frag.qsb"
    }

    FrameAnimation {
        running: mist.visible && !mist.frozen
        onTriggered: fx.time += frameTime
    }
}
