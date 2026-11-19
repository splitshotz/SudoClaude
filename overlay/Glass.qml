import QtQuick

// Liquid-glass body for the pill. `backdrop` is a texture of what's behind the
// pill, covering `target`'s parent (a live screen capture in the overlay).
// `lumTexture` is the smoothed brightness behind it, for labels that follow the
// glass.
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
    property real tintAlpha: 0.3
    property color lightColor: "#f4f4f6"
    property real lightAlpha: 0.5
    property vector4d tint: Qt.vector4d(tintColor.r, tintColor.g, tintColor.b, tintAlpha)
    property vector4d lightTint: Qt.vector4d(lightColor.r, lightColor.g, lightColor.b, lightAlpha)
    // Brightness band over which the glass goes from dark to light.
    property real lo: 0.45
    property real hi: 0.72
    readonly property alias lumTexture: lumSrc
    property size size: Qt.size(width, height)
    visible: backdrop !== null
    // Where the pill sits on the screen the backdrop covers.
    property point origin: target ? Qt.point(target.x, target.y) : Qt.point(0, 0)
    property size screen: target && target.parent ? Qt.size(target.parent.width, target.parent.height)
                                                  : Qt.size(1, 1)
    property var backdropTex: glass.backdrop
    property var lumTex: lumSrc
    fragmentShader: Qt.resolvedUrl("shaders/glass.frag.qsb")

    ShaderEffect {
        id: probe
        width: 1; height: 1
        property size size: glass.size
        property point origin: glass.origin
        property size screen: glass.screen
        property real pad: glass.pad
        property real rate: 0.06
        property var backdropTex: glass.backdrop
        property var prevTex: lumSrc
        fragmentShader: Qt.resolvedUrl("shaders/lum.frag.qsb")
    }
    ShaderEffectSource {
        id: lumSrc
        width: 0; height: 0
        sourceItem: probe
        hideSource: true
        live: true
        recursive: true
        format: ShaderEffectSource.RGBA16F
        textureSize: Qt.size(1, 1)
    }
}
