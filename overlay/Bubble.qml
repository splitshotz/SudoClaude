import QtQuick

// Claude's typed reply, in the same glass as the pill. It grows out of the
// pill like a droplet: starts small at the pill's edge, springs out past full
// size and settles, with its lens growing in as it appears.
Item {
    id: bubble

    property string text: ""
    property bool shown: false
    property Item backdrop: null
    property real mode: 0
    property real surround: 0.1
    property real tilt: 0
    property real frost: 6
    property real lens: 1
    property real tintMix: 0.12
    property color textColor: "white"
    property string fontFamily: "Google Sans Flex"
    // Which side the pill is on, so it grows out of that edge.
    property int origin: Item.Bottom
    property real maxTextWidth: 460
    property real maxHeight: 320

    readonly property real padX: 18
    readonly property real padY: 13

    TextMetrics {
        id: tm
        font: label.font
        text: bubble.text
    }
    readonly property real textW: Math.min(maxTextWidth, Math.ceil(tm.advanceWidth) + 2)
    readonly property real wantW: Math.max(64, textW + 2 * padX)
    readonly property real wantH: Math.min(maxHeight, label.implicitHeight + 2 * padY)

    width: wantW
    height: wantH
    Behavior on width { SpringAnimation { spring: 3.6; damping: 0.36; epsilon: 0.3 } }
    Behavior on height { SpringAnimation { spring: 3.6; damping: 0.36; epsilon: 0.3 } }

    property real appear: shown && text.length ? 1 : 0
    Behavior on appear {
        SpringAnimation { spring: bubble.appear > 0.5 ? 3.2 : 4.5; damping: bubble.appear > 0.5 ? 0.3 : 0.5; epsilon: 0.003 }
    }
    visible: appear > 0.005
    opacity: Math.min(1, appear * 1.6)
    transformOrigin: origin
    scale: 0.55 + 0.45 * appear

    Glass {
        id: glass
        backdrop: bubble.backdrop
        target: bubble
        radius: Math.min(22, bubble.height / 2)
        band: 9 * Math.max(0, Math.min(1, bubble.appear)) * Math.max(0.3, bubble.lens)
        frost: bubble.frost
        lens: bubble.lens
        tintMix: bubble.tintMix
        mode: bubble.mode
        surround: bubble.surround
        tilt: bubble.tilt
    }

    Item {
        anchors.fill: parent
        anchors.leftMargin: bubble.padX
        anchors.rightMargin: bubble.padX
        anchors.topMargin: bubble.padY
        anchors.bottomMargin: bubble.padY
        clip: true
        Text {
            id: label
            // Long replies keep their newest lines in view.
            anchors.bottom: parent.bottom
            width: bubble.textW
            text: bubble.text
            wrapMode: Text.Wrap
            color: bubble.textColor
            font.family: bubble.fontFamily
            font.pixelSize: 15
            lineHeight: 1.18
        }
    }
}
