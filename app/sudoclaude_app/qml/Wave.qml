import QtQuick
import "."

ShaderEffect {
    id: w
    property bool running: true
    height: 14
    property size size: Qt.size(width, height)
    property real phase: 0
    property real head: 0
    property real len: 0.3
    property vector4d activeColor: Qt.vector4d(Theme.accentFill.r, Theme.accentFill.g, Theme.accentFill.b, 1)
    property vector4d track: Qt.vector4d(Theme.accentSoft.r, Theme.accentSoft.g, Theme.accentSoft.b, 1)
    NumberAnimation on phase { running: w.running; from: 0; to: 6.2831 * 100; duration: 100000; loops: Animation.Infinite }
    SequentialAnimation on head {
        running: w.running
        loops: Animation.Infinite
        NumberAnimation { from: 0.0; to: 1.3; duration: 1800; easing.type: Easing.InOutCubic }
    }
    SequentialAnimation on len {
        running: w.running
        loops: Animation.Infinite
        NumberAnimation { from: 0.1; to: 0.45; duration: 900; easing.type: Easing.OutQuad }
        NumberAnimation { from: 0.45; to: 0.1; duration: 900; easing.type: Easing.InQuad }
    }
    fragmentShader: Qt.resolvedUrl("shaders/wave.frag.qsb")
}
