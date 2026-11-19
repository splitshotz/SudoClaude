import QtQuick
import QtQuick.Effects

// Liquid-glass status pill. On Hyprland the backdrop blur comes from the
// compositor (layerrule blur on this layer). `backdrop` is only set by the
// preview renderer to simulate that blur.
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
    signal stopRequested()

    readonly property color accent: "#D97757"
    readonly property color accentHi: "#EBA286"
    readonly property color ink: "#FBF6F2"
    readonly property string fontFamily: "Inter"
    readonly property real r: height / 2

    implicitHeight: 40
    implicitWidth: row.implicitWidth + 30
    width: implicitWidth
    height: implicitHeight
    Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }

    // soft drop shadow
    RectangularShadow {
        anchors.fill: glass
        radius: pill.r
        blur: 22
        spread: -2
        offset.y: 6
        color: Qt.rgba(0, 0, 0, 0.32)
    }

    Item {
        id: glass
        anchors.fill: parent

        // (preview only) simulated compositor backdrop blur
        Item {
            id: backdropView
            anchors.fill: parent
            visible: pill.backdrop !== null
            layer.enabled: visible
            layer.effect: MultiEffect {
                maskEnabled: true
                maskSource: shapeMask
            }
            ShaderEffectSource {
                id: bsrc
                anchors.fill: parent
                visible: false
                live: true
                sourceItem: pill.backdrop
                sourceRect: {
                    if (!pill.backdrop) return Qt.rect(0, 0, 0, 0)
                    const p = pill.mapToItem(pill.backdrop, 0, 0)
                    return Qt.rect(p.x, p.y, pill.width, pill.height)
                }
            }
            MultiEffect {
                anchors.fill: parent
                source: bsrc
                blurEnabled: true
                blur: 1.0
                blurMax: 40
                saturation: 0.25
            }
        }

        // tint
        Rectangle {
            anchors.fill: parent
            radius: pill.r
            color: Qt.rgba(0.11, 0.095, 0.085, pill.solid ? 0.78 : 0.52)
        }
        // warm light bleeding up from the bottom edge
        Rectangle {
            anchors.fill: parent
            radius: pill.r
            gradient: Gradient {
                GradientStop { position: 0.55; color: Qt.rgba(0.85, 0.47, 0.34, 0.0) }
                GradientStop { position: 1.0;  color: Qt.rgba(0.85, 0.47, 0.34, 0.16) }
            }
        }
        // specular highlight across the top
        Rectangle {
            anchors.fill: parent
            anchors.margins: 1
            radius: pill.r - 1
            gradient: Gradient {
                GradientStop { position: 0.0;  color: Qt.rgba(1, 1, 1, 0.16) }
                GradientStop { position: 0.45; color: Qt.rgba(1, 1, 1, 0.025) }
                GradientStop { position: 1.0;  color: Qt.rgba(1, 1, 1, 0.0) }
            }
        }
        // gradient rim light (bright top edge, faint bottom)
        Rectangle {
            id: rimFill
            anchors.fill: parent
            visible: false
            layer.enabled: true
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.55) }
                GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, 0.12) }
                GradientStop { position: 1.0; color: Qt.rgba(0.95, 0.65, 0.52, 0.35) }
            }
        }
        Rectangle {
            id: rimMask
            anchors.fill: parent
            radius: pill.r
            color: "transparent"
            border.width: 1
            border.color: "white"
            visible: false
            layer.enabled: true
        }
        MultiEffect {
            anchors.fill: parent
            source: rimFill
            maskEnabled: true
            maskSource: rimMask
        }
    }

    Rectangle {
        id: shapeMask
        anchors.fill: parent
        radius: pill.r
        visible: false
        layer.enabled: true
    }

    Row {
        id: row
        anchors.verticalCenter: parent.verticalCenter
        x: 16
        spacing: 10

        Row {
            visible: pill.voice === "listening"
            spacing: 2.5
            anchors.verticalCenter: parent.verticalCenter
            Repeater {
                model: 4
                Rectangle {
                    required property int index
                    property real phase: 0
                    width: 3
                    radius: 1.5
                    anchors.verticalCenter: parent.verticalCenter
                    height: 4 + 12 * Math.min(1, pill.level * (0.6 + 0.4 * Math.abs(Math.sin(phase + index * 1.3))))
                    Behavior on height { NumberAnimation { duration: 90 } }
                    color: pill.accent
                    NumberAnimation on phase {
                        running: pill.voice === "listening"
                        from: 0; to: Math.PI * 2; duration: 900; loops: Animation.Infinite
                    }
                }
            }
        }
        Item {
            visible: pill.voice !== "listening"
            width: 10; height: 10
            anchors.verticalCenter: parent.verticalCenter
            Rectangle {
                anchors.centerIn: parent
                width: 10; height: 10; radius: 5
                color: pill.accent
                SequentialAnimation on scale {
                    running: pill.running && !pill.stopped
                    loops: Animation.Infinite
                    NumberAnimation { from: 1; to: 2.4; duration: 1500; easing.type: Easing.OutCubic }
                    PauseAnimation { duration: pill.idle ? 900 : 200 }
                }
                opacity: Math.max(0, 0.6 * (2.4 - scale) / 1.4)
            }
            Rectangle {
                anchors.centerIn: parent
                width: 8; height: 8; radius: 4
                color: pill.stopped ? "#8C817C" : pill.accent
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.25)
            }
        }
        Text {
            text: pill.status
            color: pill.ink
            font.family: pill.fontFamily
            font.pixelSize: 13
            font.weight: Font.Medium
            anchors.verticalCenter: parent.verticalCenter
            style: Text.Raised
            styleColor: Qt.rgba(0, 0, 0, 0.18)
        }
        Text {
            visible: pill.subtitle.length > 0
            text: pill.subtitle
            width: Math.min(implicitWidth, 560)
            elide: pill.voice === "listening" ? Text.ElideLeft : Text.ElideRight
            color: Qt.rgba(1, 1, 1, 0.62)
            font.family: pill.fontFamily
            font.pixelSize: 13
            anchors.verticalCenter: parent.verticalCenter
        }
        Rectangle {
            width: 1; height: 16
            color: Qt.rgba(1, 1, 1, 0.16)
            anchors.verticalCenter: parent.verticalCenter
        }
        Rectangle {
            id: stopBtn
            height: 28
            radius: 14
            width: stopRow.implicitWidth + 20
            anchors.verticalCenter: parent.verticalCenter
            color: stopMouse.containsMouse ? Qt.rgba(0.851, 0.467, 0.341, 0.30)
                                           : Qt.rgba(1, 1, 1, 0.09)
            border.width: 1
            border.color: stopMouse.containsMouse ? Qt.rgba(0.92, 0.6, 0.48, 0.6)
                                                  : Qt.rgba(1, 1, 1, 0.16)
            Behavior on color { ColorAnimation { duration: 150 } }
            Row {
                id: stopRow
                anchors.centerIn: parent
                spacing: 7
                Text {
                    text: pill.stopped ? "Stopped" : "Stop"
                    color: pill.ink
                    font.family: pill.fontFamily
                    font.pixelSize: 12
                    font.weight: Font.Medium
                    anchors.verticalCenter: parent.verticalCenter
                }
                Rectangle {
                    visible: pill.detail.length > 0 && !pill.stopped
                    height: 18; radius: 5
                    width: keyText.implicitWidth + 10
                    color: Qt.rgba(1, 1, 1, 0.10)
                    border.width: 1
                    border.color: Qt.rgba(1, 1, 1, 0.20)
                    anchors.verticalCenter: parent.verticalCenter
                    Text {
                        id: keyText
                        anchors.centerIn: parent
                        text: pill.detail
                        color: Qt.rgba(1, 1, 1, 0.72)
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
