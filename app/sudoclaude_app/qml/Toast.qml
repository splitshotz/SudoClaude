import QtQuick
import "."

// A short glass note at the bottom.
Item {
    id: t
    property string text: ""
    width: label.implicitWidth + 44
    height: 46
    opacity: 0
    scale: 0.85
    function show(msg) { text = msg; anim.restart() }
    Glass { radius: 23; band: 9 }
    Text {
        id: label
        anchors.centerIn: parent
        text: t.text
        color: Theme.text
        font.family: Theme.sans
        font.pixelSize: 15
        font.weight: Font.Medium
    }
    SequentialAnimation {
        id: anim
        ParallelAnimation {
            NumberAnimation { target: t; property: "opacity"; to: 1; duration: 160 }
            SpringAnimation { target: t; property: "scale"; to: 1; spring: 4; damping: 0.4 }
        }
        PauseAnimation { duration: 2600 }
        ParallelAnimation {
            NumberAnimation { target: t; property: "opacity"; to: 0; duration: 260 }
            NumberAnimation { target: t; property: "scale"; to: 0.92; duration: 260 }
        }
    }
}
