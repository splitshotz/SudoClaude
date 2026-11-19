import QtQuick

Item {
    id: badge

    property bool shown: false
    property bool capturing: false
    property string status: "Working"
    property string detail: "Esc"
    property string transcript: ""
    property string voice: ""
    property real level: 0
    property bool stopped: false
    property bool idle: false
    property Item backdrop: null
    signal stopRequested()
    readonly property Item pillItem: pill

    implicitWidth: Math.max(pill.width + 140, 380)
    implicitHeight: 170

    property real fade: shown ? 1 : 0
    Behavior on fade { NumberAnimation { duration: shown ? 450 : 700; easing.type: Easing.OutCubic } }
    opacity: capturing ? 0 : fade

    MistLayer {
        anchors.fill: parent
        halo: true
        seed: 21.5
        radius: pill.height / 2
        spread: 26
        downscale: 2
        level: badge.level
        rx: pill.x
        ry: pill.y
        rw: pill.width
        rh: pill.height
        intensity: badge.fade * (badge.idle ? 0.55 : 0.85) * (1 + 0.6 * badge.level)
    }

    Pill {
        id: pill
        anchors.right: parent.right
        anchors.rightMargin: 30
        anchors.top: parent.top
        anchors.topMargin: 74 + (badge.shown ? 0 : -10)
        Behavior on anchors.topMargin { NumberAnimation { duration: 480; easing.type: Easing.OutCubic } }
        solid: badge.backdrop === null
        status: badge.status
        detail: badge.detail
        subtitle: badge.transcript
        voice: badge.voice
        level: badge.level
        stopped: badge.stopped
        idle: badge.idle
        running: badge.fade > 0
        backdrop: badge.backdrop
        onStopRequested: badge.stopRequested()
    }
}
