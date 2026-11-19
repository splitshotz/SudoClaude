import QtQuick

// Glass lip: a thin specular edge and a faint inner glow, drawn over the
// compositor's blur.
ShaderEffect {
    property real radius: height / 2
    property real strength: 1
    property size size: Qt.size(width, height)
    fragmentShader: Qt.resolvedUrl("shaders/rim.frag.qsb")
}
