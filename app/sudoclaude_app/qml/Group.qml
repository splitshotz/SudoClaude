import QtQuick
import "."

// A run of rows that reads as one rounded block, split by thin gaps: big outer
// corners, small inner ones (Material Expressive lists, Apple's grouped style).
Column {
    id: g
    property string title: ""
    property string note: ""
    width: parent ? parent.width : 600
    spacing: 3

    function arrange() {
        var rows = []
        for (var i = 0; i < children.length; i++) {
            var c = children[i]
            if (c.visible && c.groupRow !== undefined) rows.push(c)
        }
        for (var j = 0; j < rows.length; j++)
            rows[j].pos = rows.length === 1 ? 0 : j === 0 ? 1 : j === rows.length - 1 ? 3 : 2
    }
    onChildrenChanged: Qt.callLater(arrange)
    Component.onCompleted: arrange()
    onVisibleChildrenChanged: Qt.callLater(arrange)

    Text {
        visible: g.title !== ""
        text: g.title
        color: Theme.dim
        font.family: Theme.sans
        font.pixelSize: 13
        font.weight: Font.DemiBold
        leftPadding: 18
        bottomPadding: 6
        topPadding: 6
    }
}
