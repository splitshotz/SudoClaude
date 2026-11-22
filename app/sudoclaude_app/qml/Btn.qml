import QtQuick
import "."

// Material Expressive button: a pill that squares up a little while pressed.
Item {
    id: b
    property string text: ""
    property string icon: ""
    property string kind: "filled"   // filled, tonal, outlined, text, danger
    property bool active: true
    property bool busy: false
    property bool small: false
    signal clicked()

    implicitHeight: small ? 34 : 40
    implicitWidth: row.implicitWidth + (text ? (small ? 28 : 36) : 0) + (text ? 0 : implicitHeight)
    opacity: active ? 1 : 0.42
    Behavior on opacity { NumberAnimation { duration: 160 } }

    readonly property color fill: kind === "filled" ? Theme.accentFill
                                : kind === "tonal" ? Theme.accentSoft
                                : kind === "danger" ? Theme.badSoft : "transparent"
    readonly property color ink: kind === "filled" ? Theme.inkOnAccent
                               : kind === "tonal" ? Theme.accentInk
                               : kind === "danger" ? Theme.bad
                               : kind === "text" ? Theme.accent : Theme.text

    Rectangle {
        id: shape
        anchors.centerIn: parent
        width: parent.width
        height: parent.height
        radius: ma.pressed ? height * 0.26 : height / 2
        Behavior on radius { SpringAnimation { spring: 5; damping: 0.38; epsilon: 0.1 } }
        color: b.fill
        border.width: b.kind === "outlined" ? 1 : 0
        border.color: Theme.rgba(Theme.text, 0.22)
        scale: ma.pressed ? 0.97 : 1
        Behavior on scale { SpringAnimation { spring: 6; damping: 0.4; epsilon: 0.002 } }
        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            color: b.ink
            opacity: ma.pressed ? 0.12 : ma.containsMouse ? 0.07 : 0
            Behavior on opacity { NumberAnimation { duration: 120 } }
        }
    }
    Row {
        id: row
        anchors.centerIn: parent
        spacing: 8
        Icon {
            visible: b.icon !== "" || b.busy
            name: b.busy ? "progress_activity" : b.icon
            size: b.small ? 18 : 20
            color: b.ink
            anchors.verticalCenter: parent.verticalCenter
            RotationAnimator on rotation { running: b.busy; from: 0; to: 360; duration: 900; loops: Animation.Infinite }
        }
        Text {
            visible: b.text !== ""
            text: b.text
            color: b.ink
            font.family: Theme.sans
            font.pixelSize: b.small ? 13 : 14
            font.weight: Font.DemiBold
            font.variableAxes: ({ "ROND": 100 })
            anchors.verticalCenter: parent.verticalCenter
        }
    }
    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        enabled: b.active && !b.busy
        cursorShape: Qt.PointingHandCursor
        onClicked: b.clicked()
    }
}
