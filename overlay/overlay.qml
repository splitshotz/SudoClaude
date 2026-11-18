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
    property int rippleSeq: 0
    property real rippleX: 0
    property real rippleY: 0
    property var sock: null

    function send(obj) {
        if (shell.sock) { shell.sock.write(JSON.stringify(obj) + "\n"); shell.sock.flush() }
    }

    function handle(m) {
        if (m.active !== undefined) shell.active = m.active
        if (m.capturing !== undefined) shell.capturing = m.capturing
        if (m.stopped !== undefined) shell.stopped = m.stopped
        if (m.idle !== undefined) shell.idle = m.idle
        if (m.status !== undefined) shell.status = m.status
        if (m.detail !== undefined) shell.detail = m.detail
        if (m.action !== undefined) shell.action = m.action
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
            Component.onCompleted: shell.sock = conn
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
            visible: shell.active || content.fade > 0.002
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
                originX: win.modelData.x
                originY: win.modelData.y
                active: shell.active
                capturing: shell.capturing
                stopped: shell.stopped
                idle: shell.idle
                status: shell.status
                detail: shell.detail
                action: shell.action
                cursorX: shell.cx
                cursorY: shell.cy
                focused: shell.focusScreen === "" || shell.focusScreen === win.modelData.name

                showPill: false

                Connections {
                    target: shell
                    function onRippleSeqChanged() { content.ripple(shell.rippleX, shell.rippleY) }
                }
            }
        }
    }

    // own layer so Hyprland can blur just the pill
    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: pillWin
            required property var modelData
            screen: modelData
            readonly property bool here: shell.focusScreen === "" || shell.focusScreen === modelData.name
            visible: here && (shell.active || pillWrap.opacity > 0.01)
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
                opacity: shell.capturing ? 0 : fade
                property real fade: shell.active ? 1 : 0
                Behavior on fade { NumberAnimation { duration: shell.active ? 450 : 700; easing.type: Easing.OutCubic } }
                transform: Translate {
                    y: shell.active ? 0 : 14
                    Behavior on y { NumberAnimation { duration: 520; easing.type: Easing.OutCubic } }
                }
                Pill {
                    id: pill
                    anchors.centerIn: parent
                    status: shell.status
                    detail: shell.detail
                    stopped: shell.stopped
                    idle: shell.idle
                    running: shell.active
                    onStopRequested: shell.send({ event: "stop" })
                }
            }
        }
    }
}
