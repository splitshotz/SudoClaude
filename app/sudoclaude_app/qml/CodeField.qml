import QtQuick
import "."

// Six boxes for the pairing code from the phone.
Item {
    id: c
    property string code: ""
    signal done(string code)
    width: 6 * 48 + 5 * 8
    height: 58
    function clear() { code = ""; input.text = ""; input.forceActiveFocus() }
    TextInput {
        id: input
        width: 1; height: 1
        opacity: 0
        maximumLength: 6
        inputMethodHints: Qt.ImhDigitsOnly
        validator: RegularExpressionValidator { regularExpression: /[0-9]{0,6}/ }
        onTextChanged: { c.code = text; if (text.length === 6) c.done(text) }
    }
    Row {
        spacing: 8
        Repeater {
            model: 6
            Rectangle {
                required property int index
                readonly property bool here: input.activeFocus && index === Math.min(5, c.code.length)
                width: 48
                height: 58
                radius: 14
                color: Theme.surfaceHi
                border.width: here ? 2 : 0
                border.color: Theme.accentFill
                Text {
                    anchors.centerIn: parent
                    text: c.code.charAt(parent.index)
                    color: Theme.text
                    font.family: Theme.sans
                    font.pixelSize: 26
                    font.weight: Font.Medium
                    scale: text ? 1 : 0.5
                    Behavior on scale { SpringAnimation { spring: 6; damping: 0.4 } }
                }
            }
        }
    }
    MouseArea { anchors.fill: parent; cursorShape: Qt.IBeamCursor; onClicked: input.forceActiveFocus() }
}
