import QtQuick
import "."

// A scrolling page in the content layer. It runs under the floating toolbar, which
// refracts it, and starts to the right of the sidebar.
Item {
    id: page
    property string title: ""
    property string subtitle: ""
    property real leftInset: 0
    property real maxWidth: 720
    readonly property real scrolled: flick.contentY
    readonly property real columnX: col.x
    readonly property real columnWidth: col.width
    default property alias content: body.data
    property alias header: headerSlot.data

    Flickable {
        id: flick
        anchors.fill: parent
        contentHeight: col.height + 96
        boundsBehavior: Flickable.DragOverBounds
        flickableDirection: Flickable.VerticalFlick
        Column {
            id: col
            readonly property real avail: page.width - page.leftInset
            width: Math.min(page.maxWidth, avail - 72)
            x: page.leftInset + (avail - width) / 2
            topPadding: 96
            spacing: 28
            Column {
                width: parent.width
                spacing: 8
                Text {
                    width: parent.width
                    text: page.title
                    color: Theme.text
                    font.family: Theme.serif
                    font.pixelSize: 44
                    font.variableAxes: ({ "opsz": 72, "wght": 400 })
                    wrapMode: Text.Wrap
                }
                Text {
                    width: parent.width
                    visible: page.subtitle !== ""
                    text: page.subtitle
                    color: Theme.dim
                    font.family: Theme.sans
                    font.pixelSize: 16
                    wrapMode: Text.Wrap
                    lineHeight: 1.18
                }
            }
            Item {
                id: headerSlot
                width: parent.width
                height: childrenRect.height
                visible: children.length > 0
            }
            Column {
                id: body
                width: parent.width
                spacing: 26
            }
        }
    }
}
