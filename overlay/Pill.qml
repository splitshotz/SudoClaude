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
    signal stopRequested()

    function c(key, fallback) { return pal && pal[key] ? pal[key] : fallback }
    readonly property color accent: "#D97757"
    readonly property color surface: c("surface_container_high", "#2a2a2b")
    readonly property color onSurface: c("on_surface", "#e4e2e3")
    readonly property color onSurfaceVariant: c("on_surface_variant", "#c8c6c7")
    readonly property color outline: c("outline_variant", "#474748")
    readonly property color tonal: c("secondary_container", "#42474e")
    readonly property color onTonal: c("on_secondary_container", "#dee3eb")
    readonly property string fontFamily: "Google Sans Flex"
    readonly property bool listening: voice === "listening"

    implicitHeight: 48
    implicitWidth: row.implicitWidth + 14 + 8
    height: implicitHeight
    width: implicitWidth

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: Qt.rgba(pill.surface.r, pill.surface.g, pill.surface.b, pill.solid ? 0.94 : 0.72)
        border.width: 1
        border.color: Qt.rgba(pill.outline.r, pill.outline.g, pill.outline.b, 0.55)
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
                    color: pill.onSurface
                    family: pill.fontFamily
                    pixelSize: 14
                    weight: Font.Medium
                }
            }

            Item {
                id: sub
                anchors.verticalCenter: parent.verticalCenter
                height: subText.implicitHeight
                width: pill.subtitle.length ? Math.min(subText.implicitWidth, 520) + 10 : 0
                Behavior on width { SpringAnimation { spring: 4.2; damping: 0.42; epsilon: 0.3 } }
                clip: true
                Text {
                    id: subText
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: pill.subtitle
                    color: pill.onSurfaceVariant
                    font.family: pill.fontFamily
                    font.pixelSize: 14
                }
                opacity: pill.subtitle.length ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 180 } }
            }

            Item { width: 12; height: 1 }
            Rectangle {
                id: stopBtn
                anchors.verticalCenter: parent.verticalCenter
                height: 34
                width: stopRow.implicitWidth + 24
                radius: stopMouse.pressed ? 9 : stopMouse.containsMouse ? 12 : height / 2
                Behavior on radius { SpringAnimation { spring: 6; damping: 0.5 } }
                color: stopMouse.containsMouse ? Qt.lighter(pill.tonal, 1.18) : pill.tonal
                Behavior on color { ColorAnimation { duration: 140 } }
                scale: stopMouse.pressed ? 0.95 : 1
                Behavior on scale { SpringAnimation { spring: 7; damping: 0.5 } }
                Row {
                    id: stopRow
                    anchors.centerIn: parent
                    spacing: 8
                    Text {
                        text: pill.stopped ? "Stopped" : "Stop"
                        color: pill.onTonal
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
                        border.color: Qt.rgba(pill.onTonal.r, pill.onTonal.g, pill.onTonal.b, 0.35)
                        anchors.verticalCenter: parent.verticalCenter
                        Text {
                            id: keyText
                            anchors.centerIn: parent
                            text: pill.detail
                            color: Qt.rgba(pill.onTonal.r, pill.onTonal.g, pill.onTonal.b, 0.8)
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
