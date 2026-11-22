import QtQuick
import "."

// A glass dialog over a dimmed window. It grows its lens in as it appears.
Item {
    id: s
    property bool open: false
    property string title: ""
    property string icon: ""
    property real cardWidth: 520
    default property alias content: body.data
    signal dismissed()
    anchors.fill: parent
    visible: t > 0.01
    z: 50

    property real t: open ? 1 : 0
    Behavior on t { SpringAnimation { spring: 3.4; damping: 0.5; epsilon: 0.002 } }

    Rectangle {
        anchors.fill: parent
        color: "#000000"
        opacity: Math.min(1, s.t) * (Theme.dark ? 0.45 : 0.28)
        MouseArea { anchors.fill: parent; onClicked: s.dismissed() }
    }
    Item {
        id: card
        width: Math.min(s.cardWidth, s.width - 80)
        height: body.implicitHeight + 64
        anchors.centerIn: parent
        anchors.verticalCenterOffset: (1 - s.t) * 24
        scale: 0.9 + 0.1 * s.t
        opacity: Math.min(1, s.t * 1.6)
        Glass { radius: 30; band: 14 * Math.min(1, s.t); margin: 24 }
        MouseArea { anchors.fill: parent }
        Column {
            id: body
            x: 32
            y: 32
            width: parent.width - 64
            spacing: 18
            Row {
                spacing: 12
                visible: s.title !== ""
                Icon { visible: s.icon !== ""; name: s.icon; size: 26; color: Theme.accent; anchors.verticalCenter: parent.verticalCenter }
                Text {
                    text: s.title
                    color: Theme.text
                    font.family: Theme.serif
                    font.pixelSize: 28
                    font.variableAxes: ({ "opsz": 48, "wght": 450 })
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }
    }
}
