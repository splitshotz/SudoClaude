import QtQuick
import QtQuick.Effects
import QtQuick.Shapes

// One monitor's worth of the "Claude is using your computer" overlay.
// Pure QtQuick so it can be previewed outside Quickshell.
Item {
    id: root

    // ---- inputs ---------------------------------------------------------
    property real originX: 0          // monitor position in global layout
    property real originY: 0
    property bool active: false
    property bool focused: true       // Claude is acting on this monitor
    property bool capturing: false    // hide instantly for screenshots
    property bool stopped: false
    property bool idle: false         // no recent action ("thinking")
    property real cursorX: -10000     // global logical coordinates
    property real cursorY: -10000
    property string status: "Working"
    property string detail: "Esc"
    property string action: ""        // short verb shown on the cursor tag
    signal stopRequested()

    // ---- palette ---------------------------------------------------------
    readonly property color accent: "#D97757"
    readonly property color accentHi: "#EBA286"
    readonly property color ink: "#F6EEE9"
    readonly property color muted: Qt.rgba(0.965, 0.933, 0.914, 0.56)
    readonly property string fontFamily: "Inter"

    readonly property real lx: cursorX - originX
    readonly property real ly: cursorY - originY
    readonly property bool cursorHere: lx > -60 && ly > -60 && lx < width + 60 && ly < height + 60

    // fade is animated; capturing hides instantly (and restores instantly)
    property real fade: active ? 1 : 0
    Behavior on fade { NumberAnimation { duration: root.active ? 450 : 700; easing.type: Easing.OutCubic } }
    opacity: capturing ? 0 : fade

    // ---- edge glow ---------------------------------------------------------
    property real breathe: 0.7
    SequentialAnimation on breathe {
        running: root.fade > 0 && !root.capturing
        loops: Animation.Infinite
        NumberAnimation { to: 1.0;  duration: 1900; easing.type: Easing.InOutSine }
        NumberAnimation { to: 0.55; duration: 1900; easing.type: Easing.InOutSine }
    }

    Item {
        id: glow
        anchors.fill: parent
        opacity: root.focused ? (root.idle ? 0.55 : 1) : 0
        Behavior on opacity { NumberAnimation { duration: 600; easing.type: Easing.InOutSine } }

        Rectangle {
            id: glowSource
            anchors.fill: parent
            color: "transparent"
            border.width: 14
            border.color: root.stopped ? "#8C817C" : root.accent
            visible: false
            layer.enabled: true
        }
        MultiEffect {
            anchors.fill: parent
            source: glowSource
            blurEnabled: true
            blur: 1.0
            blurMax: 64
            opacity: 0.85 * root.breathe
        }
        Rectangle {
            id: coreSource
            anchors.fill: parent
            color: "transparent"
            border.width: 4
            border.color: root.stopped ? "#A39893" : root.accentHi
            visible: false
            layer.enabled: true
        }
        MultiEffect {
            anchors.fill: parent
            source: coreSource
            blurEnabled: true
            blur: 1.0
            blurMax: 14
            opacity: 0.9 * root.breathe
        }
        Rectangle {
            anchors.fill: parent
            color: "transparent"
            border.width: 2
            border.color: Qt.rgba(0.96, 0.7, 0.58, 0.7 * root.breathe)
        }
    }

    // ---- click ripple --------------------------------------------------------
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

    // ---- Claude's cursor ---------------------------------------------------------
    Item {
        id: cursor
        visible: root.cursorHere
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

    // embedded only for previews; under Quickshell the pill gets its own layer
    property bool showPill: true
    property Item backdrop: null
    Pill {
        id: pillItem
        visible: root.showPill && root.focused
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 26 + (root.active ? 0 : -14)
        Behavior on anchors.bottomMargin { NumberAnimation { duration: 520; easing.type: Easing.OutCubic } }
        status: root.status
        detail: root.detail
        stopped: root.stopped
        idle: root.idle
        running: root.fade > 0
        backdrop: root.backdrop
        onStopRequested: root.stopRequested()
    }
}
