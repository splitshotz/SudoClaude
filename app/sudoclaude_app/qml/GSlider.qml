import QtQuick
import "."

// Slider with an orange fill and a glass knob that swells while you hold it.
Item {
    id: sl
    property real from: 0
    property real to: 1
    property real value: 0
    property real step: 0
    property int decimals: 1
    property string suffix: ""
    property bool showValue: true
    signal moved(real value)

    implicitWidth: 260
    implicitHeight: 36

    readonly property real frac: (value - from) / Math.max(1e-6, to - from)
    function snap(v) {
        v = Math.max(from, Math.min(to, v))
        if (step > 0) v = Math.round((v - from) / step) * step + from
        return v
    }

    Text {
        id: readout
        visible: sl.showValue
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: 52
        horizontalAlignment: Text.AlignRight
        text: sl.value.toFixed(sl.decimals) + sl.suffix
        color: Theme.dim
        font.family: Theme.sans
        font.pixelSize: 13
        font.features: { "tnum": 1 }
    }
    Item {
        id: track
        anchors.left: parent.left
        anchors.right: readout.visible ? readout.left : parent.right
        anchors.rightMargin: readout.visible ? 12 : 0
        anchors.verticalCenter: parent.verticalCenter
        height: 6
        Rectangle { anchors.fill: parent; radius: 3; color: Theme.faint }
        Rectangle {
            width: knob.x + knob.width / 2
            height: parent.height
            radius: 3
            color: Theme.accent
        }
        Item {
            id: knob
            width: 24; height: 24
            anchors.verticalCenter: parent.verticalCenter
            x: sl.frac * (track.width - width)
            scale: drag.pressed ? 1.25 : 1
            Behavior on scale { SpringAnimation { spring: 5; damping: 0.4; epsilon: 0.002 } }
            GlassSurface {
                target: knob
                radius: 12
                band: 7
                margin: 10
                tintColor: "#FFFFFF"
                lightColor: "#FFFFFF"
                tintMix: 0.5
            }
        }
        MouseArea {
            id: drag
            anchors.fill: parent
            anchors.margins: -12
            cursorShape: Qt.PointingHandCursor
            function at(mx) {
                const f = (mx - 12 - knob.width / 2) / Math.max(1, track.width - knob.width)
                sl.moved(sl.snap(sl.from + f * (sl.to - sl.from)))
            }
            onPressed: e => at(e.x)
            onPositionChanged: e => { if (pressed) at(e.x) }
        }
    }
}
