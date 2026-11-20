import QtQuick
import "."

// Single-line text field on a quiet tray.
Item {
    id: f
    property alias text: input.text
    property string placeholder: ""
    signal edited(string text)
    implicitWidth: 240
    implicitHeight: 38
    Rectangle {
        anchors.fill: parent
        radius: 12
        color: Theme.faint
        border.width: input.activeFocus ? 1.5 : 1
        border.color: input.activeFocus ? Theme.accent : Theme.rgba(Theme.text, 0.08)
        Behavior on border.color { ColorAnimation { duration: 160 } }
    }
    TextInput {
        id: input
        anchors.fill: parent
        anchors.leftMargin: 14
        anchors.rightMargin: 14
        verticalAlignment: TextInput.AlignVCenter
        color: Theme.text
        selectionColor: Theme.accent
        font.family: Theme.sans
        font.pixelSize: 14
        clip: true
        onEditingFinished: f.edited(text)
        Text {
            visible: !input.text.length
            anchors.verticalCenter: parent.verticalCenter
            text: f.placeholder
            color: Theme.dim
            font: input.font
        }
    }
}
