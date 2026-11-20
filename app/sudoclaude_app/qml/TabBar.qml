import QtQuick
import "."

// Floating glass tab bar with a lozenge that springs between tabs and stretches
// on the way, like a drop of the same glass.
Item {
    id: bar
    property var tabs: []             // [{id, label}]
    property string current: ""
    signal picked(string id)

    implicitHeight: 52
    implicitWidth: row.implicitWidth + 12
    readonly property int index: Math.max(0, tabs.findIndex(t => t.id === current))

    GlassSurface { target: bar; radius: bar.height / 2; band: 11 }

    Item {
        id: lozenge
        y: 6
        height: bar.height - 12
        property Item cur: row.children.length > bar.index ? row.children[bar.index] : null
        property real tx: cur ? row.x + cur.x : 6
        property real tw: cur ? cur.width : 0
        property real lx: tx
        property real rx: tx + tw
        // Leading edge moves first, trailing edge follows: a liquid stretch.
        Behavior on lx { SpringAnimation { spring: lozenge.tx < lozenge.lx ? 5 : 3.2; damping: 0.45; epsilon: 0.3 } }
        Behavior on rx { SpringAnimation { spring: lozenge.tx + lozenge.tw > lozenge.rx ? 5 : 3.2; damping: 0.45; epsilon: 0.3 } }
        x: lx
        width: Math.max(0, rx - lx)
        GlassSurface {
            target: lozenge
            radius: lozenge.height / 2
            band: 9
            margin: 12
            tintColor: Theme.accent
            lightColor: Theme.accent
            tintMix: 0.62
        }
    }
    Row {
        id: row
        x: 6
        anchors.verticalCenter: parent.verticalCenter
        Repeater {
            model: bar.tabs
            Item {
                required property var modelData
                required property int index
                width: label.implicitWidth + 40
                height: bar.height - 12
                Text {
                    id: label
                    anchors.centerIn: parent
                    text: modelData.label
                    color: index === bar.index ? "white" : Theme.text
                    Behavior on color { ColorAnimation { duration: 200 } }
                    font.family: Theme.sans
                    font.pixelSize: 15
                    font.weight: Font.DemiBold
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: bar.picked(modelData.id)
                }
            }
        }
    }
}
