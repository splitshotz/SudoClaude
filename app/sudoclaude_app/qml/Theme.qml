pragma Singleton
import QtQuick

// Colors, type and shared glass plumbing for the whole app.
QtObject {
    id: t
    property bool dark: true
    // Set by Main: the animated background (and a texture of it) that every
    // piece of glass refracts, and a frame tick so glass follows scrolling.
    property Item scene: null
    property Item backdrop: null
    property int tick: 0
    // Bumped whenever config.json changes, so bindings that read settings refresh.
    property int cfgRev: 0
    // Live glass settings, mirrored from config.json so the sliders preview here.
    property real frost: 5
    property real lens: 1
    property real tintMix: 0.12

    readonly property color accent: "#D97757"
    readonly property color accentDeep: "#B9583A"
    readonly property color accentSoft: "#EBA383"
    readonly property color base: dark ? "#171210" : "#F6F1EA"
    readonly property color text: dark ? "#EDE5DA" : "#221A16"
    readonly property color dim: dark ? "#A99F96" : "#6E6259"
    // The italic accent word in headlines, like Zen's "calmer".
    readonly property color accentText: dark ? "#E8825F" : "#C9552F"
    // Primary pill: cream on dark, ink on light.
    readonly property color pill: dark ? "#EDE4D8" : "#2A201B"
    readonly property color pillText: dark ? "#1E1714" : "#F6F1EA"
    readonly property color faint: dark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.07)
    readonly property color good: dark ? "#8FD19E" : "#2F8F4A"
    readonly property color warn: dark ? "#F0B35E" : "#B06A12"
    readonly property color bad: dark ? "#F08A7A" : "#B23A2A"
    readonly property real mode: dark ? 0 : 1
    readonly property real surround: dark ? 0.10 : 0.90

    readonly property string serif: "Instrument Serif"
    readonly property string sans: "Inter"

    function rgba(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }
}
