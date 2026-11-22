import QtQuick
import "."

// Material 3 Expressive slider: a thick rounded track split by a slim handle,
// with the value floating above it while you drag.
Item {
    id: s
    property real from: 0
    property real to: 1
    property real step: 0
    property real value: 0
    property int decimals: 1
    property string suffix: ""
    property var format: null
    property bool active: true
    property bool showValue: true
    readonly property real labelW: showValue ? 62 : 0
    signal moved(real value)
    width: 260
    height: 44
    opacity: active ? 1 : 0.4

    property real shown: value
    readonly property real frac: to > from ? Math.max(0, Math.min(1, (shown - from) / (to - from))) : 0
    readonly property string label: format ? format(shown)
                                           : (Number(shown).toFixed(decimals).replace(/\.0+$/, "") + suffix)
    readonly property real trackX: labelW > 0 ? labelW + 14 : 0
    readonly property real trackW: width - trackX
    readonly property real hx: trackX + 2 + frac * (trackW - 4)
    readonly property real gap: 6

    onValueChanged: if (!ma.pressed) shown = value

    Text {
        visible: s.showValue
        width: s.labelW
        anchors.verticalCenter: parent.verticalCenter
        horizontalAlignment: Text.AlignRight
        text: s.label
        color: Theme.dim
        font.family: Theme.sans
        font.pixelSize: 14
        font.features: { "tnum": 1 }
    }
    Rectangle {   // active part
        x: s.trackX
        width: Math.max(0, s.hx - s.gap - s.trackX)
        height: 16
        radius: 8
        anchors.verticalCenter: parent.verticalCenter
        color: Theme.accentFill
        topRightRadius: 3
        bottomRightRadius: 3
    }
    Rectangle {   // rest
        x: s.hx + s.gap
        width: Math.max(0, s.width - s.hx - s.gap)
        height: 16
        radius: 8
        anchors.verticalCenter: parent.verticalCenter
        color: Theme.accentSoft
        topLeftRadius: 3
        bottomLeftRadius: 3
    }
    Rectangle {   // handle
        width: ma.pressed ? 2 : 4
        height: 40
        radius: 2
        x: s.hx - width / 2
        anchors.verticalCenter: parent.verticalCenter
        color: Theme.accentFill
        Behavior on width { NumberAnimation { duration: 120 } }
    }
    Rectangle {   // value bubble
        width: valText.implicitWidth + 20
        height: 30
        radius: 15
        color: Theme.text
        x: s.hx - width / 2
        y: -30
        opacity: ma.pressed ? 1 : 0
        scale: ma.pressed ? 1 : 0.6
        transformOrigin: Item.Bottom
        Behavior on opacity { NumberAnimation { duration: 130 } }
        Behavior on scale { SpringAnimation { spring: 5; damping: 0.45 } }
        Text {
            id: valText
            anchors.centerIn: parent
            text: s.label
            color: Theme.bg
            font.family: Theme.sans
            font.pixelSize: 13
            font.weight: Font.DemiBold
        }
    }
    MouseArea {
        id: ma
        x: s.trackX - 6
        width: s.trackW + 12
        height: parent.height + 12
        y: -6
        enabled: s.active
        cursorShape: Qt.PointingHandCursor
        preventStealing: true
        function pick(mx) {
            var f = Math.max(0, Math.min(1, (mx - s.trackX - 2) / (s.trackW - 4)))
            var v = s.from + f * (s.to - s.from)
            if (s.step > 0) v = Math.round(v / s.step) * s.step
            v = Math.max(s.from, Math.min(s.to, v))
            if (v !== s.shown) { s.shown = v; s.moved(v) }
        }
        onPressed: m => pick(m.x)
        onPositionChanged: m => { if (pressed) pick(m.x) }
    }
}
