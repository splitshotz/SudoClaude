import QtQuick
import "."

// A small glass note that rises from the bottom and leaves on its own.
Item {
    id: toast
    property string text: ""
    function show(t) { text = t; up = 1; hide.restart() }
    property real up: 0
    Behavior on up { SpringAnimation { spring: 3.6; damping: 0.42; epsilon: 0.003 } }
    Timer { id: hide; interval: 2600; onTriggered: toast.up = 0 }
    width: label.implicitWidth + 44
    height: 46
    opacity: Math.min(1, up * 1.5)
    visible: up > 0.01
    transform: Translate { y: (1 - toast.up) * 40 }
    GlassSurface { target: toast; radius: toast.height / 2 }
    Text {
        id: label
        anchors.centerIn: parent
        text: toast.text
        color: Theme.text
        font.family: Theme.sans
        font.pixelSize: 14
        font.weight: Font.Medium
    }
}
