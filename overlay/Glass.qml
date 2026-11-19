import QtQuick

// Liquid-glass body for the pill. `backdrop` shows what's behind the pill in the
// same coordinates as `target`'s parent (a live screen capture in the overlay);
// only a small patch around the pill is copied each frame. `lumTexture` is the
// smoothed brightness behind it, for labels that follow the glass.
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
    property var backdropTex: patch
    property var lumTex: lumSrc
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

    ShaderEffect {
        id: probe
        width: 1; height: 1
        property size size: glass.size
        property real pad: glass.pad
        property real rate: 0.06
        property var backdropTex: patch
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
