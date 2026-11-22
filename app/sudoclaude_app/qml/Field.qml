import QtQuick
import "."

// A filled text field with Material's active indicator.
Item {
    id: f
    property alias text: input.text
    property string placeholder: ""
    property bool mono: false
    property int maxLength: 200
    signal edited(string text)
    signal accepted()
    width: 240
    height: 44
    Rectangle {
        anchors.fill: parent
        radius: 12
        color: Theme.surfaceHi
        Rectangle {
            anchors.bottom: parent.bottom
            anchors.horizontalCenter: parent.horizontalCenter
            width: input.activeFocus ? parent.width - 24 : 0
            height: 2
            radius: 1
            color: Theme.accentFill
            Behavior on width { SpringAnimation { spring: 4; damping: 0.5 } }
        }
    }
    TextInput {
        id: input
        anchors.fill: parent
        anchors.leftMargin: 14
        anchors.rightMargin: 14
        verticalAlignment: TextInput.AlignVCenter
        color: Theme.text
        selectionColor: Theme.accentSoft
        selectedTextColor: Theme.accentInk
        font.family: f.mono ? "monospace" : Theme.sans
        font.pixelSize: 15
        maximumLength: f.maxLength
        clip: true
        onEditingFinished: f.edited(text)
        onAccepted: f.accepted()
        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: !input.text && !input.activeFocus
            text: f.placeholder
            color: Theme.faint
            font: input.font
        }
    }
}
