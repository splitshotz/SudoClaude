import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Io

ShellRoot {
    id: shell

    property bool active: false
    property bool capturing: false
    property bool stopped: false
    property bool idle: false
    property real cx: -10000
    property real cy: -10000
    property string status: "Working"
    property string detail: "Esc"
    property string action: ""
    property string focusScreen: ""
    property string mode: "full"
    property string side: "right"
    property real winX: 0
    property real winY: 0
    property real winW: 0
    property real winH: 0
    property string voice: ""
    property string transcript: ""
    property real level: 0
    property int rippleSeq: 0
    property real rippleX: 0
    property real rippleY: 0
    property var sockets: []

    readonly property bool present: active || voice !== ""

    function send(obj) {
        const line = JSON.stringify(obj) + "\n"
        for (const s of shell.sockets) {
            try { s.write(line); s.flush() } catch (e) {}
        }
    }

    function handle(m) {
        for (const k of ["active", "capturing", "stopped", "idle", "status", "detail", "action",
                         "mode", "side", "winX", "winY", "winW", "winH", "voice", "transcript",
                         "level"]) {
            if (m[k] !== undefined) shell[k] = m[k]
        }
        if (m.screen !== undefined) shell.focusScreen = m.screen
        if (m.x !== undefined && m.y !== undefined) { shell.cx = m.x; shell.cy = m.y }
        if (m.click) { shell.rippleX = shell.cx; shell.rippleY = shell.cy; shell.rippleSeq++ }
        if (m.quit) Qt.quit()
    }

    SocketServer {
        active: true
        path: Quickshell.env("SUDOCLAUDE_SOCK")
        handler: Socket {
            id: conn
            onConnectedChanged: {
                if (connected) shell.sockets = shell.sockets.concat([conn])
                else shell.sockets = shell.sockets.filter(s => s !== conn)
            }
            parser: SplitParser {
                onRead: data => {
                    try { shell.handle(JSON.parse(data)) } catch (e) { console.warn("bad msg", e) }
                }
            }
        }
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: win
            required property var modelData
            screen: modelData
            readonly property bool here: shell.focusScreen === "" || shell.focusScreen === modelData.name
            visible: here && shell.mode !== "corner" && (shell.present || content.fade > 0.002)
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"
            mask: Region {}
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "claude-computer-use"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            OverlayContent {
                id: content
                anchors.fill: parent
                showPill: false
                originX: win.modelData.x
                originY: win.modelData.y
                active: shell.active
                capturing: shell.capturing
                stopped: shell.stopped
                idle: shell.idle
                status: shell.status
                detail: shell.detail
                action: shell.action
                mode: shell.mode
                side: shell.side
                winX: shell.winX
                winY: shell.winY
                winW: shell.winW
                winH: shell.winH
                voice: shell.voice
                transcript: shell.transcript
                level: shell.level
                cursorX: shell.cx
                cursorY: shell.cy
                focused: win.here

                Connections {
                    target: shell
                    function onRippleSeqChanged() { content.ripple(shell.rippleX, shell.rippleY) }
                }
            }
        }
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: pillWin
            required property var modelData
            screen: modelData
            readonly property bool here: shell.focusScreen === "" || shell.focusScreen === modelData.name
            visible: here && shell.mode !== "corner" && (shell.present || pillWrap.opacity > 0.01)
            anchors { bottom: true }
            margins { bottom: 26 }
            implicitWidth: pill.width + 40
            implicitHeight: pill.height + 24
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "claude-cu-glass"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            mask: Region { item: pill }

            Item {
                id: pillWrap
                anchors.fill: parent
                property real fade: shell.present && shell.mode !== "corner" ? 1 : 0
                Behavior on fade { NumberAnimation { duration: shell.present ? 450 : 700; easing.type: Easing.OutCubic } }
                opacity: shell.capturing ? 0 : fade
                transform: Translate {
                    y: shell.present ? 0 : 14
                    Behavior on y { NumberAnimation { duration: 520; easing.type: Easing.OutCubic } }
                }
                Pill {
                    id: pill
                    anchors.centerIn: parent
                    status: shell.status
                    detail: shell.detail
                    subtitle: shell.transcript
                    voice: shell.voice
                    level: shell.level
                    stopped: shell.stopped
                    idle: shell.idle
                    running: shell.present
                    onStopRequested: shell.send({ event: "stop" })
                }
            }
        }
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: cornerWin
            required property var modelData
            screen: modelData
            readonly property bool here: shell.focusScreen === "" || shell.focusScreen === modelData.name
            visible: here && shell.mode === "corner" && (shell.present || badge.opacity > 0.01)
            anchors { top: true; right: true }
            implicitWidth: badge.implicitWidth
            implicitHeight: badge.implicitHeight
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "claude-cu-corner"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            mask: Region { item: badge.pillItem }

            CornerBadge {
                id: badge
                anchors.fill: parent
                shown: shell.present && shell.mode === "corner"
                capturing: shell.capturing
                status: shell.status
                detail: shell.detail
                transcript: shell.transcript
                voice: shell.voice
                level: shell.level
                stopped: shell.stopped
                idle: shell.idle
                onStopRequested: shell.send({ event: "stop" })
            }
        }
    }
}
