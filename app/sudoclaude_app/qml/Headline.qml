import QtQuick
import "."

// Big lowercase serif headline. Wrap the words to accent in *asterisks*: they
// come out in italic, in Claude's orange.
Text {
    id: h
    property string source: ""
    property int size: 108
    property bool centered: true
    text: source.replace(/\*([^*]+)\*/g,
            "<i><font color='" + Theme.accentText + "'>$1</font></i>").replace(/\n/g, "<br>")
    textFormat: Text.StyledText
    color: Theme.text
    font.family: Theme.serif
    font.pixelSize: size
    lineHeight: 0.96
    horizontalAlignment: centered ? Text.AlignHCenter : Text.AlignLeft
    wrapMode: Text.Wrap
}
