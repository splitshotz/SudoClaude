import QtQuick
import "."

// An overview card: an expressive shape holding the icon, a status chip, a title
// and a line about what's going on. The shape turns a little on hover.
Item {
    id: tile
    property string icon: ""
    property string title: ""
    property string detail: ""
    property string chip: ""
    property string chipTone: "neutral"
    property real lobes: 8
    property color tone: Theme.accentSoft
    property color ink: Theme.accentInk
    signal clicked()
    height: 176

    Rectangle {
        anchors.fill: parent
        radius: ma.pressed ? 20 : 28
        Behavior on radius { SpringAnimation { spring: 4; damping: 0.4 } }
        color: Theme.surface
        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            color: Theme.text
            opacity: ma.pressed ? 0.07 : ma.containsMouse ? 0.035 : 0
            Behavior on opacity { NumberAnimation { duration: 120 } }
        }
    }
    Item {
        x: 22; y: 22
        width: 54; height: 54
        Blob {
            anchors.fill: parent
            tone: tile.tone
            lobes: tile.lobes
            depth: tile.lobes > 6 ? 0.08 : 0.12
            spin: ma.containsMouse ? 0.5 : 0
            Behavior on spin { SpringAnimation { spring: 2.2; damping: 0.35 } }
        }
        Icon { anchors.centerIn: parent; name: tile.icon; size: 26; fill: 1; color: tile.ink }
    }
    Chip {
        visible: tile.chip !== ""
        anchors.right: parent.right
        anchors.rightMargin: 18
        y: 22
        text: tile.chip
        tone: tile.chipTone
    }
    Column {
        x: 24
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 22
        width: parent.width - 48
        spacing: 4
        Text {
            text: tile.title
            color: Theme.text
            font.family: Theme.sans
            font.pixelSize: 18
            font.weight: Font.DemiBold
            font.variableAxes: ({ "ROND": 60 })
        }
        Text {
            width: parent.width
            text: tile.detail
            color: Theme.dim
            font.family: Theme.sans
            font.pixelSize: 13
            wrapMode: Text.Wrap
            maximumLineCount: 2
            elide: Text.ElideRight
        }
    }
    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: tile.clicked()
    }
}
