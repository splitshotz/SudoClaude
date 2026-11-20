import QtQuick
import "."

// A row of choices with a glass lozenge that springs to the selected one.
Item {
    id: seg
    property var options: []          // [{value, label}]
    property var value
    signal picked(var value)

    implicitHeight: 38
    implicitWidth: row.implicitWidth + 8
    readonly property int index: Math.max(0, options.findIndex(o => o.value === value))

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: Theme.faint
    }
    Item {
        id: lozenge
        y: 4
        height: seg.height - 8
        property Item cur: row.children.length > seg.index ? row.children[seg.index] : null
        x: cur ? row.x + cur.x : 4
        width: cur ? cur.width : 0
        Behavior on x { SpringAnimation { spring: 4; damping: 0.4; epsilon: 0.3 } }
        Behavior on width { SpringAnimation { spring: 4; damping: 0.4; epsilon: 0.3 } }
        GlassSurface {
            target: lozenge
            radius: lozenge.height / 2
            band: 8
            margin: 10
            tintColor: Theme.dark ? "#3A322D" : "#FFFFFF"
            lightColor: tintColor
            tintMix: 0.5
        }
    }
    Row {
        id: row
        x: 4
        anchors.verticalCenter: parent.verticalCenter
        Repeater {
            model: seg.options
            Item {
                required property var modelData
                required property int index
                width: lbl.implicitWidth + 30
                height: seg.height - 8
                Text {
                    id: lbl
                    anchors.centerIn: parent
                    text: modelData.label
                    color: index === seg.index ? Theme.text : Theme.dim
                    Behavior on color { ColorAnimation { duration: 180 } }
                    font.family: Theme.sans
                    font.pixelSize: 14
                    font.weight: index === seg.index ? Font.DemiBold : Font.Normal
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: seg.picked(modelData.value)
                }
            }
        }
    }
}
