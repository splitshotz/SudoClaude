import QtQuick
import QtQuick.Effects
import QtQuick.Shapes

Item {
    id: root

    property real originX: 0
    property real originY: 0
    property bool active: false
    property bool focused: true
    property bool capturing: false
    property bool stopped: false
    property bool idle: false
    property real cursorX: -10000
    property real cursorY: -10000
    property string status: "Working"
    property string detail: "Esc"
    property string action: ""
    property string mode: "full"
    property string side: "right"
    property real winX: 0
    property real winY: 0
    property real winW: 0
    property real winH: 0
    property string voice: ""
    property string transcript: ""
    property real level: 0
    property bool showPill: true
    property Item backdrop: null
    signal stopRequested()

    readonly property color accent: "#D97757"
    readonly property color accentHi: "#EBA286"
    readonly property string fontFamily: "Inter"

    readonly property real lx: cursorX - originX
    readonly property real ly: cursorY - originY
    readonly property bool cursorHere: lx > -60 && ly > -60 && lx < width + 60 && ly < height + 60
    readonly property bool listening: voice === "listening"
    readonly property bool shown: (active || voice !== "") && mode !== "corner"

    property real fade: shown ? 1 : 0
    Behavior on fade { NumberAnimation { duration: root.shown ? 500 : 800; easing.type: Easing.OutCubic } }
    opacity: capturing ? 0 : fade

    property real breathe: 1
    SequentialAnimation on breathe {
        running: root.fade > 0 && !root.capturing
        loops: Animation.Infinite
        NumberAnimation { to: 1.12; duration: 2600; easing.type: Easing.InOutSine }
        NumberAnimation { to: 0.88; duration: 2600; easing.type: Easing.InOutSine }
    }

    property real smoothLevel: 0
    Behavior on smoothLevel { NumberAnimation { duration: 120 } }
    onLevelChanged: smoothLevel = level

    readonly property bool edgeMode: active && (mode === "full" || mode === "side")
    readonly property real edgeTarget: !root.focused ? 0
        : listening && !edgeMode ? 0.55 + 0.9 * smoothLevel
        : mode === "full" ? (idle ? 0.55 : 0.8)
        : mode === "side" ? 0.5
        : 0

    MistLayer {
        id: edgeMist
        anchors.fill: parent
        seed: 3.7
        level: root.smoothLevel
        intensity: root.edgeTarget * root.breathe
        Behavior on intensity { NumberAnimation { duration: 700; easing.type: Easing.InOutSine } }
        el: (root.mode === "full" || (root.mode === "side" && root.side === "left")) && root.edgeMode ? 1 : 0
        er: (root.mode === "full" || (root.mode === "side" && root.side === "right")) && root.edgeMode ? 1 : 0
        et: root.mode === "full" && root.edgeMode ? 0.85 : 0
        eb: root.mode === "full" && root.edgeMode ? 1 : (root.listening && !root.edgeMode ? 1.15 : 0)
        Behavior on el { NumberAnimation { duration: 900; easing.type: Easing.InOutCubic } }
        Behavior on er { NumberAnimation { duration: 900; easing.type: Easing.InOutCubic } }
        Behavior on et { NumberAnimation { duration: 900; easing.type: Easing.InOutCubic } }
        Behavior on eb { NumberAnimation { duration: 900; easing.type: Easing.InOutCubic } }
        spread: root.mode === "side" ? 80 : root.listening && !root.edgeMode ? 130 : 105
        Behavior on spread { NumberAnimation { duration: 900; easing.type: Easing.InOutCubic } }
    }

    MistLayer {
        id: haloMist
        anchors.fill: parent
        halo: true
        seed: 11.2
        radius: 14
        spread: 34
        level: root.smoothLevel
        rx: root.winX - root.originX
        ry: root.winY - root.originY
        rw: Math.max(1, root.winW)
        rh: Math.max(1, root.winH)
        Behavior on rx { NumberAnimation { duration: 650; easing.type: Easing.InOutCubic } }
        Behavior on ry { NumberAnimation { duration: 650; easing.type: Easing.InOutCubic } }
        Behavior on rw { NumberAnimation { duration: 650; easing.type: Easing.InOutCubic } }
        Behavior on rh { NumberAnimation { duration: 650; easing.type: Easing.InOutCubic } }
        intensity: root.focused && root.active && root.mode === "window" && root.winW > 0
                   ? (root.idle ? 0.6 : 0.95) * root.breathe : 0
        Behavior on intensity { NumberAnimation { duration: 700; easing.type: Easing.InOutSine } }
    }

    Component {
        id: rippleComp
        Item {
            id: rp
            Rectangle {
                id: disk
                anchors.centerIn: parent
                width: 6; height: 6; radius: width / 2
                color: Qt.rgba(0.851, 0.467, 0.341, 0.38)
            }
            Rectangle {
                id: ring
                anchors.centerIn: parent
                width: 6; height: 6; radius: width / 2
                color: "transparent"
                border.width: 2.5
                border.color: root.accent
            }
            ParallelAnimation {
                running: true
                NumberAnimation { target: ring; properties: "width,height"; to: 56; duration: 560; easing.type: Easing.OutCubic }
                NumberAnimation { target: ring; property: "opacity"; from: 1; to: 0; duration: 560; easing.type: Easing.OutQuad }
                NumberAnimation { target: disk; properties: "width,height"; to: 34; duration: 380; easing.type: Easing.OutCubic }
                NumberAnimation { target: disk; property: "opacity"; from: 1; to: 0; duration: 420; easing.type: Easing.OutQuad }
                onFinished: rp.destroy()
            }
        }
    }

    function ripple(gx, gy) {
        const x = gx - originX, y = gy - originY
        if (x < -60 || y < -60 || x > width + 60 || y > height + 60) return
        rippleComp.createObject(rippleLayer, { x: x, y: y })
        press.restart()
    }

    Item { id: rippleLayer; anchors.fill: parent }

    Item {
        id: cursor
        visible: root.cursorHere && root.active && (root.mode === "full" || root.mode === "window")
        x: root.lx
        y: root.ly
        Behavior on x { NumberAnimation { duration: 300; easing.type: Easing.OutQuint } }
        Behavior on y { NumberAnimation { duration: 300; easing.type: Easing.OutQuint } }
        opacity: root.idle ? 0.75 : 1
        Behavior on opacity { NumberAnimation { duration: 400 } }

        Item {
            id: pointer
            width: 24; height: 24
            transformOrigin: Item.TopLeft
            scale: 1
            SequentialAnimation {
                id: press
                NumberAnimation { target: pointer; property: "scale"; to: 0.82; duration: 70; easing.type: Easing.OutQuad }
                NumberAnimation { target: pointer; property: "scale"; to: 1.0; duration: 260; easing.type: Easing.OutBack; easing.overshoot: 2.2 }
            }
            Shape {
                id: arrow
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                layer.enabled: true
                layer.samples: 8
                layer.effect: MultiEffect {
                    shadowEnabled: true
                    shadowColor: Qt.rgba(0.12, 0.05, 0.02, 0.55)
                    shadowBlur: 0.45
                    shadowVerticalOffset: 1.5
                    shadowHorizontalOffset: 0.5
                }
                ShapePath {
                    strokeColor: "#FFFFFF"
                    strokeWidth: 1.8
                    joinStyle: ShapePath.RoundJoin
                    fillGradient: LinearGradient {
                        x1: 4; y1: 3; x2: 16; y2: 19
                        GradientStop { position: 0; color: root.stopped ? "#A39893" : root.accentHi }
                        GradientStop { position: 1; color: root.stopped ? "#8C817C" : root.accent }
                    }
                    startX: 4.5; startY: 3.5
                    PathLine { x: 7.6;  y: 20.2 }
                    PathQuad { x: 9.4; y: 19.9; controlX: 8.3; controlY: 20.9 }
                    PathLine { x: 11.6; y: 15.6 }
                    PathLine { x: 18.4; y: 14.9 }
                    PathQuad { x: 18.9; y: 13.2; controlX: 19.8; controlY: 14.3 }
                    PathLine { x: 6.2;  y: 3.0 }
                    PathQuad { x: 4.5; y: 3.5; controlX: 4.9; controlY: 2.3 }
                }
            }
        }

        Rectangle {
            id: tag
            x: 16; y: 20
            height: 22
            radius: 11
            width: tagRow.implicitWidth + 18
            Behavior on width { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
            color: root.stopped ? "#8C817C" : root.accent
            clip: true
            layer.enabled: true
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowColor: Qt.rgba(0.12, 0.05, 0.02, 0.45)
                shadowBlur: 0.5
                shadowVerticalOffset: 1.5
            }
            Row {
                id: tagRow
                anchors.verticalCenter: parent.verticalCenter
                x: 9
                spacing: 5
                Text {
                    text: "Claude"
                    color: "white"
                    font.family: root.fontFamily
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                    anchors.verticalCenter: parent.verticalCenter
                }
                Text {
                    visible: root.action.length > 0
                    text: root.action
                    color: Qt.rgba(1, 1, 1, 0.78)
                    font.family: root.fontFamily
                    font.pixelSize: 12
                    font.weight: Font.Medium
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }
    }


    Pill {
        id: pillItem
        visible: root.showPill && root.focused && root.mode !== "corner"
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 26 + (root.shown ? 0 : -14)
        Behavior on anchors.bottomMargin { NumberAnimation { duration: 520; easing.type: Easing.OutCubic } }
        status: root.status
        detail: root.detail
        subtitle: root.transcript
        voice: root.voice
        level: root.smoothLevel
        stopped: root.stopped
        idle: root.idle
        running: root.fade > 0
        backdrop: root.backdrop
        onStopRequested: root.stopRequested()
    }
}
