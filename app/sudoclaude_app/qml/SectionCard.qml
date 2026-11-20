import QtQuick
import "."

// A settings section: serif title, a quiet Reset link, then its rows.
GlassCard {
    id: sc
    property string title: ""
    property string subtitle: ""
    property string section: ""
    default property alias rows: list.data
    width: parent ? parent.width : 600
    height: header.height + list.implicitHeight + 2 * padding + 8
    padding: 30

    Item {
        id: header
        width: sc.width - 2 * sc.padding
        height: heading.implicitHeight + (sub.visible ? sub.implicitHeight + 4 : 0) + 8
        Text {
            id: heading
            text: sc.title
            color: Theme.text
            font.family: Theme.serif
            font.pixelSize: 38
        }
        Text {
            id: sub
            visible: sc.subtitle.length
            anchors.top: heading.bottom
            anchors.topMargin: 2
            text: sc.subtitle
            color: Theme.dim
            font.family: Theme.sans
            font.pixelSize: 14
        }
        Text {
            id: reset
            visible: sc.section.length
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.topMargin: 14
            text: "Reset to defaults"
            color: resetArea.containsMouse ? Theme.accent : Theme.dim
            Behavior on color { ColorAnimation { duration: 150 } }
            font.family: Theme.sans
            font.pixelSize: 13
            font.weight: Font.Medium
            MouseArea {
                id: resetArea
                anchors.fill: parent
                anchors.margins: -8
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: backend.resetSection(sc.section)
            }
        }
    }
    Column {
        id: list
        anchors.top: header.bottom
        anchors.topMargin: 8
        width: sc.width - 2 * sc.padding
    }
}
