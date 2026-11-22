import QtQuick
import "."

// Material 3 Expressive connected button group: the chosen segment fills and
// rounds into a full pill while its neighbours keep tight inner corners.
Row {
    id: g
    property var options: []      // [{value, label, icon?}]
    property var value
    property bool active: true
    signal picked(var value)
    spacing: 2
    opacity: active ? 1 : 0.4

    Repeater {
        model: g.options
        Item {
            id: seg
            required property var modelData
            required property int index
            readonly property bool on: g.value === modelData.value
            readonly property bool first: index === 0
            readonly property bool last: index === g.options.length - 1
            width: lab.implicitWidth + 32 + ((modelData.icon || on) ? 24 : 0)
            Behavior on width { SpringAnimation { spring: 5; damping: 0.45; epsilon: 0.2 } }
            height: 38
            Rectangle {
                anchors.fill: parent
                readonly property real outer: height / 2
                readonly property real inner: seg.on ? height / 2 : (ma.pressed ? 12 : 6)
                topLeftRadius: seg.first ? outer : inner
                bottomLeftRadius: seg.first ? outer : inner
                topRightRadius: seg.last ? outer : inner
                bottomRightRadius: seg.last ? outer : inner
                Behavior on topLeftRadius { SpringAnimation { spring: 5; damping: 0.4 } }
                Behavior on bottomLeftRadius { SpringAnimation { spring: 5; damping: 0.4 } }
                Behavior on topRightRadius { SpringAnimation { spring: 5; damping: 0.4 } }
                Behavior on bottomRightRadius { SpringAnimation { spring: 5; damping: 0.4 } }
                color: seg.on ? Theme.accentFill : Theme.surfaceHi
                Behavior on color { ColorAnimation { duration: 160 } }
                Rectangle {
                    anchors.fill: parent
                    topLeftRadius: parent.topLeftRadius; bottomLeftRadius: parent.bottomLeftRadius
                    topRightRadius: parent.topRightRadius; bottomRightRadius: parent.bottomRightRadius
                    color: Theme.text
                    opacity: ma.containsMouse && !seg.on ? 0.06 : 0
                }
            }
            Row {
                anchors.centerIn: parent
                spacing: 6
                Icon {
                    visible: !!seg.modelData.icon || seg.on
                    name: seg.on ? "check" : (seg.modelData.icon || "")
                    size: 18
                    color: seg.on ? Theme.inkOnAccent : Theme.text
                    anchors.verticalCenter: parent.verticalCenter
                    width: visible ? 18 : 0
                }
                Text {
                    id: lab
                    text: seg.modelData.label
                    color: seg.on ? Theme.inkOnAccent : Theme.text
                    font.family: Theme.sans
                    font.pixelSize: 14
                    font.weight: Font.Medium
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
            MouseArea {
                id: ma
                anchors.fill: parent
                hoverEnabled: true
                enabled: g.active
                cursorShape: Qt.PointingHandCursor
                onClicked: g.picked(seg.modelData.value)
            }
        }
    }
}
