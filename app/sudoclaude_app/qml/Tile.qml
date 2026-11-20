import QtQuick
import "."

// A choice in setup: glass that turns orange when picked.
Item {
    id: tile
    property string title
    property string body
    property bool picked
    signal toggle()
    width: 300; height: 210
    scale: tileArea.pressed ? 0.97 : tileArea.containsMouse ? 1.02 : 1
    Behavior on scale { SpringAnimation { spring: 5; damping: 0.45; epsilon: 0.002 } }
    GlassSurface {
        target: tile
        radius: 26
        tintColor: tile.picked ? Theme.accent : (Theme.dark ? "#2A2522" : "#FFFBF6")
        lightColor: tintColor
        tintMix: tile.picked ? 0.42 : Theme.tintMix
        Behavior on tintMix { NumberAnimation { duration: 240 } }
    }
    Column {
        anchors.fill: parent
        anchors.margins: 26
        spacing: 10
        Item {
            width: parent.width; height: 26
            Rectangle {
                anchors.right: parent.right
                width: 24; height: 24; radius: 12
                color: tile.picked ? Theme.pill : "transparent"
                border.width: tile.picked ? 0 : 1.5
                border.color: Theme.rgba(Theme.text, 0.35)
                Behavior on color { ColorAnimation { duration: 200 } }
                Text {
                    anchors.centerIn: parent
                    visible: tile.picked
                    text: "✓"
                    color: Theme.pillText
                    font.pixelSize: 13
                    font.weight: Font.Bold
                }
            }
        }
        Text {
            text: tile.title
            color: tile.picked && !Theme.dark ? "white" : Theme.text
            font.family: Theme.serif
            font.pixelSize: 36
        }
        Text {
            width: parent.width
            text: tile.body
            color: tile.picked && !Theme.dark ? Qt.rgba(1, 1, 1, 0.85) : Theme.dim
            font.family: Theme.sans
            font.pixelSize: 14
            wrapMode: Text.Wrap
            lineHeight: 1.2
        }
    }
    MouseArea {
        id: tileArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: tile.toggle()
    }
}
