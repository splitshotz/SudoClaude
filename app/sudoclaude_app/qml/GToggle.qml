import QtQuick
import "."

// On/off switch: a glass track that fills orange and a glass knob that springs
// across, stretching a little on the way like a droplet.
Item {
    id: tg
    property bool checked: false
    signal toggled(bool value)
    implicitWidth: 54
    implicitHeight: 32

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: tg.checked ? Theme.accent : Theme.faint
        Behavior on color { ColorAnimation { duration: 220 } }
        border.width: 1
        border.color: Theme.rgba(Theme.text, 0.08)
    }
    Item {
        id: knob
        width: 26 + stretch * 8
        height: 26
        y: 3
        property real pos: tg.checked ? 1 : 0
        Behavior on pos { SpringAnimation { spring: 4.5; damping: 0.42; epsilon: 0.002 } }
        property real stretch: Math.max(0, 1 - Math.abs(pos - 0.5) * 2) * 0.9
        x: 3 + pos * (tg.width - 6 - width)
        GlassSurface {
            target: knob
            radius: knob.height / 2
            band: 7
            margin: 10
            tintColor: "#FFFFFF"
            lightColor: "#FFFFFF"
            tintMix: 0.55
        }
    }
    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: tg.toggled(!tg.checked)
    }
}
