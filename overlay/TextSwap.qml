import QtQuick

// Label that rolls to new text: the old line drifts up and fades while the new
// one rises into place, so status changes read as motion instead of a flicker.
Item {
    id: sw
    property string text: ""
    property color color: "white"
    property string family: "Google Sans Flex"
    property int pixelSize: 14
    property int weight: Font.Medium
    // Shifts the line to centre on its cap height (see Pill.capNudge).
    property real nudge: 0

    implicitWidth: Math.max(a.implicitWidth * a.opacity, b.implicitWidth * b.opacity, cur.implicitWidth)
    implicitHeight: cur.implicitHeight
    width: cur.implicitWidth
    height: cur.implicitHeight
    clip: false

    property bool flip: false
    readonly property Text cur: flip ? b : a
    readonly property Text old: flip ? a : b

    function swap(t) {
        if (cur.text === t) return
        if (cur.text === "") { cur.text = t; return }
        flip = !flip
        cur.text = t
        enter.restart()
    }
    onTextChanged: swap(text)
    Component.onCompleted: a.text = text

    // Inline components can't see this file's ids, so styling is bound here.
    component Line: Text {
        anchors.verticalCenter: parent.verticalCenter
        property real dy: 0
        transform: Translate { y: dy }
    }
    Line {
        id: a
        color: sw.color; font.family: sw.family; font.pixelSize: sw.pixelSize; font.weight: sw.weight
        anchors.verticalCenterOffset: sw.nudge
    }
    Line {
        id: b
        opacity: 0
        color: sw.color; font.family: sw.family; font.pixelSize: sw.pixelSize; font.weight: sw.weight
        anchors.verticalCenterOffset: sw.nudge
    }

    ParallelAnimation {
        id: enter
        NumberAnimation { target: sw.cur; property: "opacity"; from: 0; to: 1; duration: 260; easing.type: Easing.OutCubic }
        NumberAnimation { target: sw.cur; property: "dy"; from: 9; to: 0; duration: 380; easing.type: Easing.OutBack; easing.overshoot: 1.4 }
        NumberAnimation { target: sw.old; property: "opacity"; to: 0; duration: 160; easing.type: Easing.OutQuad }
        NumberAnimation { target: sw.old; property: "dy"; to: -8; duration: 220; easing.type: Easing.OutCubic }
    }
}
