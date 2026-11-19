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

    property var pal: ({})
    implicitWidth: 900
    implicitHeight: 140

    property real fade: shown ? 1 : 0
    Behavior on fade { NumberAnimation { duration: shown ? 220 : 260; easing.type: Easing.OutCubic } }
    opacity: capturing ? 0 : fade

    Pill {
        id: pill
        anchors.right: parent.right
        anchors.rightMargin: 30
        anchors.top: parent.top
        anchors.topMargin: 58
        pal: badge.pal
        transformOrigin: Item.TopRight
        scale: badge.shown ? 1 : 0.86
        Behavior on scale { SpringAnimation { spring: 5; damping: 0.38; epsilon: 0.002 } }
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
