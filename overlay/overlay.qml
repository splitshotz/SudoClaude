import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import Quickshell.Hyprland

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
    property string style: "hairline"
    property var pal: ({})
    property bool typing: false
    property string winId: ""
    property real screenRadius: 23
    property real windowRadius: 18
    property string pillAt: "bottom"

    readonly property bool winGone: {
        if (winId === "" || mode !== "window") return false
        const id = winId.replace(/^0x/, "")
        return !Hyprland.toplevels.values.some(t => String(t.address).replace(/^0x/, "") === id)
    }

    FileView {
        id: posFile
        path: Quickshell.env("HOME") + "/.local/state/sudoclaude/pill.json"
        printErrors: false
        onLoaded: {
            try { shell.pillAt = JSON.parse(text()).at || "bottom" } catch (e) {}
        }
    }
    function savePill(at) {
        shell.pillAt = at
        try { posFile.setText(JSON.stringify({ at: at }) + "\n") } catch (e) {}
    }

    // The desktop's Material You palette, so the pill matches the shell.
    FileView {
        id: palFile
        path: Quickshell.env("HOME") + "/.local/state/quickshell/user/generated/colors.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try { shell.pal = JSON.parse(text()) } catch (e) {}
        }
    }
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
                         "level", "style", "typing", "winId", "screenRadius", "windowRadius"]) {
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
                style: shell.style
                winGone: shell.winGone
                screenRadius: shell.screenRadius
                windowRadius: shell.windowRadius
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
            // Stays mapped for the life of the overlay. Unmapping it while a captured
            // frame was in flight crashed Quickshell, and remapping started it at
            // zero width so the pill slid in from the left. When the pill is down
            // the window is empty and takes no input at all.
            visible: true
            // The whole screen, so the pill can be thrown anywhere (its spots keep
            // clear of bars). Only the pill takes input; everything else clicks
            // straight through.
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "claude-cu-glass"
            WlrLayershell.keyboardFocus: shell.typing && here ? WlrKeyboardFocus.Exclusive
                                                               : WlrKeyboardFocus.None
            property Region pillRegion: Region { item: stage.pill }
            property Region noRegion: Region {}
            mask: stage.on ? pillRegion : noRegion

            readonly property var reserved: {
                const m = Hyprland.monitorFor(modelData)
                const r = m && m.lastIpcObject ? m.lastIpcObject.reserved : null
                return r && r.length === 4 ? r : [0, 0, 0, 0]
            }
            Component.onCompleted: Hyprland.refreshMonitors()

            // What's behind the pill, for the glass edge to bend: one live stream
            // while the pill is up, nothing otherwise.
            ScreencopyView {
                id: behind
                anchors.fill: parent
                captureSource: pillWin.modelData
                live: stage.on && !shell.capturing
            }

            PillStage {
                id: stage
                anchors.fill: parent
                backdrop: behind
                insets: pillWin.reserved
                on: pillWin.here && shell.present && shell.mode !== "corner"
                visible: on || pill.opacity > 0.01
                capturing: shell.capturing
                at: shell.pillAt
                onMoved: at => shell.savePill(at)
                pill.pal: shell.pal
                pill.status: shell.status
                pill.detail: shell.detail
                pill.subtitle: shell.transcript
                pill.voice: shell.voice
                pill.level: shell.level
                pill.stopped: shell.stopped
                pill.idle: shell.idle
                pill.running: shell.present
                pill.typing: shell.typing && pillWin.here
                onStopRequested: shell.send({ event: "stop" })
                onTyped: text => { shell.typing = false; shell.send({ event: "typed", text: text }) }
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
            implicitWidth: 900
            implicitHeight: 140
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
                pal: shell.pal
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
