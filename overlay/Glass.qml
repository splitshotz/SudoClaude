import QtQuick

// Liquid-glass lip for the pill. `backdrop` shows what's behind the pill in the
// same coordinates as `target`'s parent (a live screen capture in the overlay).
// Only a small patch around the pill is copied each frame.
ShaderEffect {
    id: glass
    property Item backdrop: null
    property Item target: null
    property real pad: 28
    property real radius: height / 2
    property real band: 11
    property real strength: 1
    // Radians off the default light (above, slightly left); the glint slides
    // round the rim as this changes.
    property real tilt: 0
    property point lightDir: Qt.point(Math.sin(-0.57 + tilt), -Math.cos(-0.57 + tilt))
    property size size: Qt.size(width, height)
    visible: backdrop !== null
    property var backdropTex: patch
    fragmentShader: Qt.resolvedUrl("shaders/glass.frag.qsb")

    ShaderEffectSource {
        id: patch
        width: 0; height: 0
        sourceItem: glass.backdrop
        hideSource: true
        live: true
        sourceRect: glass.target ? Qt.rect(glass.target.x - glass.pad, glass.target.y - glass.pad,
                                           glass.target.width + 2 * glass.pad,
                                           glass.target.height + 2 * glass.pad)
                                 : Qt.rect(0, 0, 1, 1)
    }
}
