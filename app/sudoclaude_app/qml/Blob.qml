import QtQuick
import "."

ShaderEffect {
    id: b
    property color tone: Theme.accentSoft
    property real lobes: 8
    property real depth: 0.09
    property real spin: 0
    property vector4d color: Qt.vector4d(tone.r, tone.g, tone.b, tone.a)
    property real px: 1 / Math.max(1, width)
    width: 48
    height: 48
    fragmentShader: Qt.resolvedUrl("shaders/blob.frag.qsb")
}
