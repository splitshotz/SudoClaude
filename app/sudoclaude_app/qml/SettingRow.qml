import QtQuick
import "."

// Label and explanation on the left, a control on the right.
Item {
    id: r
    property string title: ""
    property string detail: ""
    default property alias control: slot.data
    width: parent ? parent.width : 400
    implicitHeight: Math.max(texts.implicitHeight, slot.childrenRect.height) + 22

    Column {
        id: texts
        anchors.left: parent.left
        anchors.right: slot.left
        anchors.rightMargin: 24
        anchors.verticalCenter: parent.verticalCenter
        spacing: 3
        Text {
            text: r.title
            color: Theme.text
            font.family: Theme.sans
            font.pixelSize: 15
            font.weight: Font.Medium
            width: parent.width
            wrapMode: Text.Wrap
        }
        Text {
            visible: r.detail.length
            text: r.detail
            color: Theme.dim
            font.family: Theme.sans
            font.pixelSize: 13
            width: parent.width
            wrapMode: Text.Wrap
            lineHeight: 1.15
        }
    }
    Item {
        id: slot
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: childrenRect.width
        height: childrenRect.height
    }
    Rectangle {
        anchors.bottom: parent.bottom
        width: parent.width
        height: 1
        color: Theme.faint
    }
}
