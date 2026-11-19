import QtQuick

// Status pill. Flat Material 3 surface, translucent so the compositor's blur
// shows through (layer rule on Hyprland), no gradients. Size changes ride a
// spring so a stream of transcript words never makes it stutter.
Item {
    id: pill

    property string status: "Working"
    property string detail: "Esc"
    property bool stopped: false
    property bool idle: false
    property bool running: true
    property string subtitle: ""
    property string voice: ""
    property real level: 0
    property bool solid: false
    property Item backdrop: null
    property var pal: ({})
    property bool typing: false
    property bool lifted: false
    property real tilt: 0
    property real appear: 1
    signal stopRequested()
    signal typed(string text)

    onTypingChanged: {
        if (typing) { field.text = ""; field.forceActiveFocus() }
    }

    function c(key, fallback) { return pal && pal[key] ? pal[key] : fallback }
    readonly property color accent: "#D97757"
    readonly property color surface: c("surface_container_highest", "#343536")
    // Light glass with dark labels over bright content, dark glass with light
    // labels otherwise, like Apple's small glass controls. `mode` crossfades
    // between them.
    property real mode: 0
    property real surround: 0.1
    readonly property real lightEased: !solid ? mode * mode * (3 - 2 * mode) : 0
    function blend(a, b, t) {
        const x = Qt.lighter(a, 1.0), y = Qt.lighter(b, 1.0)
        return Qt.rgba(x.r + (y.r - x.r) * t, x.g + (y.g - x.g) * t,
                       x.b + (y.b - x.b) * t, x.a + (y.a - x.a) * t)
    }
    readonly property color fg: blend(c("on_surface", "#e4e2e3"), "#1c1b1d", lightEased)
    readonly property color fgDim: blend(c("on_surface_variant", "#c8c6c7"), "#48474a", lightEased)
    readonly property color outline: c("outline_variant", "#474748")
    readonly property color tonal: blend(c("secondary_container", "#42474e"), "#dcdde2", lightEased)
    readonly property color tonalFg: blend(c("on_secondary_container", "#dee3eb"), "#1c1b1d", lightEased)
    readonly property string fontFamily: "Google Sans Flex"
    readonly property bool listening: voice === "listening"

    implicitHeight: 48
    implicitWidth: row.implicitWidth + 14 + 8
    height: implicitHeight
    width: implicitWidth

    Glass {
        id: glass
        visible: !pill.solid
        backdrop: pill.backdrop
        target: pill
        band: (pill.lifted ? 13 : 10) * pill.appear
        Behavior on band { NumberAnimation { duration: 180 } }
        tilt: pill.tilt
        mode: pill.mode
        surround: pill.surround
        tintColor: pill.surface
    }
    Rectangle {
        visible: pill.solid
        anchors.fill: parent
        radius: height / 2
        color: Qt.rgba(pill.surface.r, pill.surface.g, pill.surface.b, 0.92)
    }

    Item {
        anchors.fill: parent
        clip: true

        Row {
            id: row
            anchors.verticalCenter: parent.verticalCenter
            x: 14
            spacing: 0

            MorphDot {
                anchors.verticalCenter: parent.verticalCenter
                color: pill.accent
                listening: pill.listening
                busy: !pill.idle
                stopped: pill.stopped
                level: pill.level
            }
            Item { width: 10; height: 1 }

            Item {
                anchors.verticalCenter: parent.verticalCenter
                height: statusText.height
                width: statusText.width
                Behavior on width { SpringAnimation { spring: 4.5; damping: 0.42; epsilon: 0.3 } }
                TextSwap {
                    id: statusText
                    anchors.verticalCenter: parent.verticalCenter
                    text: pill.status
                    color: pill.fg
                    family: pill.fontFamily
                    pixelSize: 14
                    weight: Font.Medium
                }
            }

            Item {
                id: sub
                anchors.verticalCenter: parent.verticalCenter
                height: subText.implicitHeight
                width: pill.subtitle.length && !pill.typing ? Math.min(subText.implicitWidth, 520) + 10 : 0
                Behavior on width { SpringAnimation { spring: 4.2; damping: 0.42; epsilon: 0.3 } }
                clip: true
                Text {
                    id: subText
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: pill.subtitle
                    color: pill.fgDim
                    font.family: pill.fontFamily
                    font.pixelSize: 14
                }
                opacity: pill.subtitle.length && !pill.typing ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 180 } }
            }

            Item {
                anchors.verticalCenter: parent.verticalCenter
                height: 30
                width: pill.typing ? 420 : 0
                Behavior on width { SpringAnimation { spring: 4.2; damping: 0.42; epsilon: 0.3 } }
                clip: true
                opacity: pill.typing ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 160 } }
                TextInput {
                    id: field
                    x: 10
                    width: 410
                    anchors.verticalCenter: parent.verticalCenter
                    color: pill.fg
                    selectionColor: pill.accent
                    font.family: pill.fontFamily
                    font.pixelSize: 14
                    clip: true
                    Keys.onReturnPressed: { pill.typed(text); text = "" }
                    Keys.onEnterPressed: { pill.typed(text); text = "" }
                    Keys.onEscapePressed: { text = ""; pill.typed("") }
                    Text {
                        visible: !field.text.length
                        text: "Type to Claude"
                        color: pill.fgDim
                        opacity: 0.7
                        font: field.font
                    }
                }
            }

            Item { width: 12; height: 1 }
            Rectangle {
                id: stopBtn
                anchors.verticalCenter: parent.verticalCenter
                height: 34
                width: stopRow.implicitWidth + 24
                radius: stopMouse.pressed ? 9 : stopMouse.containsMouse ? 12 : height / 2
                Behavior on radius { SpringAnimation { spring: 6; damping: 0.5 } }
                // A lighter (or darker) layer of the same glass rather than a solid chip.
                readonly property real lift: stopMouse.containsMouse ? 0.07 : 0
                color: pill.solid ? pill.tonal
                     : pill.blend(Qt.rgba(1, 1, 1, 0.13 + lift), Qt.rgba(0, 0, 0, 0.07 + lift), pill.lightEased)
                Behavior on color { ColorAnimation { duration: 140 } }
                scale: stopMouse.pressed ? 0.95 : 1
                Behavior on scale { SpringAnimation { spring: 7; damping: 0.5 } }
                Row {
                    id: stopRow
                    anchors.centerIn: parent
                    spacing: 8
                    Text {
                        text: pill.stopped ? "Stopped" : "Stop"
                        color: pill.tonalFg
                        font.family: pill.fontFamily
                        font.pixelSize: 13
                        font.weight: Font.Medium
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Rectangle {
                        visible: pill.detail.length > 0 && !pill.stopped
                        height: 18; radius: 6
                        width: keyText.implicitWidth + 10
                        color: "transparent"
                        border.width: 1
                        border.color: Qt.rgba(pill.tonalFg.r, pill.tonalFg.g, pill.tonalFg.b, 0.35)
                        anchors.verticalCenter: parent.verticalCenter
                        Text {
                            id: keyText
                            anchors.centerIn: parent
                            text: pill.detail
                            color: Qt.rgba(pill.tonalFg.r, pill.tonalFg.g, pill.tonalFg.b, 0.8)
                            font.family: pill.fontFamily
                            font.pixelSize: 10
                            font.weight: Font.DemiBold
                        }
                    }
                }
                MouseArea {
                    id: stopMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: pill.stopRequested()
                }
            }
        }
    }
}
