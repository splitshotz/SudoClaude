import QtQuick
import "."

// A round icon button for toolbars and rows.
Item {
    id: b
    property string icon: ""
    property string tip: ""
    property bool spinning: false
    property color ink: Theme.text
    signal clicked()
    width: 38
    height: 38
    Rectangle {
        anchors.fill: parent
        radius: ma.pressed ? 12 : width / 2
        Behavior on radius { SpringAnimation { spring: 5; damping: 0.38 } }
        color: Theme.rgba(Theme.text, ma.pressed ? 0.12 : ma.containsMouse ? 0.07 : 0)
        Behavior on color { ColorAnimation { duration: 120 } }
    }
    Icon {
        anchors.centerIn: parent
        name: b.icon
        size: 21
        color: b.ink
        RotationAnimator on rotation { running: b.spinning; from: 0; to: 360; duration: 900; loops: Animation.Infinite }
    }
    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: b.clicked()
    }
}
