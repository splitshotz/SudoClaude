import QtQuick
import "."

// Material 3 Expressive switch: the thumb grows and gains a check when on.
Item {
    id: s
    property bool checked: false
    property bool active: true
    signal toggled(bool value)
    width: 52
    height: 32
    opacity: active ? 1 : 0.4

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: s.checked ? Theme.accentFill : Theme.surfaceHi
        border.width: s.checked ? 0 : 2
        border.color: Theme.rgba(Theme.text, 0.28)
        Behavior on color { ColorAnimation { duration: 180 } }
    }
    Rectangle {
        id: thumb
        property real d: ma.pressed ? 28 : s.checked ? 24 : 16
        width: d
        height: d
        radius: d / 2
        anchors.verticalCenter: parent.verticalCenter
        x: s.checked ? s.width - 4 - d : 8 - (d - 16) / 2
        color: s.checked ? Theme.inkOnAccent : Theme.rgba(Theme.text, 0.55)
        Behavior on d { SpringAnimation { spring: 6; damping: 0.42 } }
        Behavior on x { SpringAnimation { spring: Theme.springFast; damping: Theme.springDamp; epsilon: 0.2 } }
        Behavior on color { ColorAnimation { duration: 180 } }
        Icon {
            anchors.centerIn: parent
            name: "check"
            size: 16
            weight: 600
            color: Theme.accentFill
            opacity: s.checked ? 1 : 0
            scale: s.checked ? 1 : 0.4
            Behavior on opacity { NumberAnimation { duration: 140 } }
            Behavior on scale { SpringAnimation { spring: 5; damping: 0.4 } }
        }
    }
    MouseArea {
        id: ma
        anchors.fill: parent
        anchors.margins: -6
        enabled: s.active
        cursorShape: Qt.PointingHandCursor
        onClicked: s.toggled(!s.checked)
    }
}
