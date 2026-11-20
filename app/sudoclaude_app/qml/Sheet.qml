import QtQuick
import "."

// Modal glass sheet over a soft dim.
Item {
    id: sheet
    anchors.fill: parent
    property bool open: false
    property string title: ""
    default property alias content: body.data
    property real cardWidth: 560
    signal dismissed()

    property real t: open ? 1 : 0
    Behavior on t { SpringAnimation { spring: 3.4; damping: 0.45; epsilon: 0.003 } }
    visible: t > 0.01

    Rectangle {
        anchors.fill: parent
        color: Theme.rgba(Theme.dark ? "#000000" : "#2A1D16", 0.32 * Math.min(1, sheet.t))
        MouseArea { anchors.fill: parent; onClicked: sheet.dismissed() }
    }
    GlassCard {
        id: card
        width: sheet.cardWidth
        anchors.centerIn: parent
        height: col.implicitHeight + 2 * padding
        scale: 0.92 + 0.08 * sheet.t
        opacity: Math.min(1, sheet.t * 1.4)
        appear: sheet.t
        Column {
            id: col
            width: card.width - 2 * card.padding
            spacing: 16
            Text {
                text: sheet.title
                color: Theme.text
                font.family: Theme.serif
                font.pixelSize: 36
                width: parent.width
                wrapMode: Text.Wrap
            }
            Column { id: body; width: parent.width; spacing: 14 }
        }
    }
}
