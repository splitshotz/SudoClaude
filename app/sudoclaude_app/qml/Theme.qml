pragma Singleton
import QtQuick

// Colors, type and motion for the whole app. Warm neutrals and Claude's orange,
// Material's tonal surfaces and springs, glass only on the floating layer.
QtObject {
    id: t
    property bool dark: true

    // Set by Main: the content layer the floating glass refracts, a texture of
    // it, and a frame tick so glass keeps up with scrolling.
    property Item scene: null
    property Item backdrop: null
    property int tick: 0
    property int cfgRev: 0
    property real frost: 5
    property real lens: 1
    property real tintMix: 0.12

    readonly property color bg: dark ? "#1A1917" : "#F4F2EC"
    readonly property color surface: dark ? "#252420" : "#FFFFFF"
    readonly property color surfaceHi: dark ? "#2F2D29" : "#ECE9E1"
    readonly property color surfaceLow: dark ? "#201F1C" : "#EEEBE4"
    readonly property color line: dark ? Qt.rgba(1, 1, 1, 0.07) : Qt.rgba(0.1, 0.08, 0.05, 0.08)
    readonly property color text: dark ? "#F3F0E9" : "#1C1B19"
    readonly property color dim: dark ? "#ABA59B" : "#67635B"
    readonly property color faint: dark ? "#77726A" : "#9E998F"

    // Claude's orange. Text and icons use a deeper shade on light for contrast.
    readonly property color accent: dark ? "#E58D6C" : "#BC5733"
    readonly property color accentFill: dark ? "#D97757" : "#C9643F"
    readonly property color inkOnAccent: "#FFFFFF"
    readonly property color accentSoft: dark ? "#52301F" : "#F8E3D8"
    readonly property color accentInk: dark ? "#FFD9C9" : "#6E2C14"

    readonly property color good: dark ? "#86C79A" : "#2C7A4A"
    readonly property color goodSoft: dark ? "#203A29" : "#DDF0E2"
    readonly property color warn: dark ? "#E8BA62" : "#8F5D00"
    readonly property color warnSoft: dark ? "#3E3119" : "#F6EACB"
    readonly property color bad: dark ? "#F2907F" : "#B3261E"
    readonly property color badSoft: dark ? "#45231E" : "#F9DEDA"

    readonly property real mode: dark ? 0 : 1
    readonly property real surround: dark ? 0.10 : 0.93

    readonly property string serif: "Newsreader"
    readonly property string sans: "Google Sans Flex"
    readonly property string icons: "Material Symbols Rounded"

    // Material's expressive springs: fast spatial, a touch of bounce.
    readonly property real springFast: 4.2
    readonly property real springDamp: 0.42

    function rgba(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }
    function mix(a, b, k) { return Qt.rgba(a.r + (b.r - a.r) * k, a.g + (b.g - a.g) * k,
                                           a.b + (b.b - a.b) * k, a.a + (b.a - a.a) * k) }
}
