import QtQuick
import "."

// First run: a check, a few choices, a shortcut, the install. The left side is
// a slow arrangement of shapes; the right side holds one step at a time, with the
// navigation on a glass bar.
Item {
    id: page
    property int step: 0          // 0 welcome, 1 check, 2 choose, 3 keys, 4 install, 5 done
    readonly property int stepIndex: step
    property bool failed: false
    property bool dismissed: false
    readonly property bool holding: step >= 4 && !dismissed
    property var log: []
    property bool showLog: false

    property bool optOverlay: true
    property bool optOcr: true
    property bool optPhone: false
    property bool optVoice: false
    property bool optBrowser: false
    property string talk: "SUPER+Space"
    property string stopKey: "SUPER+SHIFT+Escape"

    readonly property real colLeft: art.width + side.colX
    readonly property real colWidth: side.colW
    readonly property var checks: backend.checks || []
    readonly property bool ready: checks.length > 0 && checks.every(x => x.ok || !x.required)
    function has(id) { var c = checks.find(x => x.id === id); return c ? c.ok : false }

    function next() {
        step = Math.min(5, step + 1)
        if (step === 4) startInstall()
    }
    function back() { step = Math.max(0, step - 1) }
    function startInstall() {
        log = []
        failed = false
        backend.install({ ocr: optOcr, voice: optVoice, browser: optBrowser, phone: optPhone,
                          talk: talk, stop: stopKey })
    }

    Connections {
        target: backend
        function onLogLine(line) {
            if (backend.busy === "install") page.log = page.log.concat([line]).slice(-400)
        }
        function onTaskFinished(task, ok, msg) {
            if (task !== "install") return
            page.failed = !ok
            if (ok && !page.optOverlay) backend.set("overlay", false)
            if (ok) backend.set("voice.enabled", page.optVoice)
            page.step = 5
        }
    }

    // ---- the composition on the left ---------------------------------------------
    Item {
        id: art
        width: Math.min(page.width * 0.42, 560)
        height: parent.height
        readonly property real cx: width * 0.5
        readonly property real cy: height * 0.5
        property real t: 0
        NumberAnimation on t { from: 0; to: Math.PI * 2; duration: 60000; loops: Animation.Infinite }

        // Same mark as the sidebar: a scalloped shape centred on the text's
        // midline with a smaller one set against its upper right.
        readonly property real d: Math.min(width * 0.7, height * 0.5)
        readonly property real mx: cx + 20
        readonly property real my: cy - 30
        Blob {
            width: art.d; height: width
            x: art.mx - width / 2
            y: art.my - height / 2
            lobes: 12; depth: 0.06
            spin: art.t * 0.5 + page.step * 0.4
            Behavior on spin { SpringAnimation { spring: 1.4; damping: 0.4 } }
            tone: Theme.accentSoft
        }
        Blob {
            width: art.d * 0.42; height: width
            x: art.mx + art.d * 0.28
            y: art.my - art.d * 0.62
            lobes: 4; depth: 0.15
            spin: -art.t + page.step * 0.6
            Behavior on spin { SpringAnimation { spring: 1.4; damping: 0.4 } }
            tone: Theme.dark ? "#2E2A3A" : "#E6E0F2"
        }
        Rectangle {
            width: 96; height: 96
            radius: 30
            x: art.mx - 48
            y: art.my - 48
            color: Theme.accentFill
            scale: 1 + 0.03 * Math.sin(art.t * 4)
            Icon { anchors.centerIn: parent; name: "arrow_selector_tool"; size: 56; fill: 1; color: Theme.inkOnAccent }
        }
    }

    // ---- the step -----------------------------------------------------------------
    Item {
        id: side
        x: art.width
        width: page.width - art.width
        height: parent.height

        component Step: Item {
            id: st
            property int index
            readonly property bool on: page.step === index
            property real t: on ? 1 : 0
            Behavior on t { NumberAnimation { duration: 420; easing.type: Easing.OutCubic } }
            anchors.fill: parent
            visible: t > 0.01
            opacity: t
            transform: Translate { y: (1 - st.t) * (page.step > st.index ? -24 : 24) }
        }
        component Title: Text {
            width: parent.width
            color: Theme.text
            font.family: Theme.serif
            font.pixelSize: 46
            font.variableAxes: ({ "opsz": 72, "wght": 400 })
            wrapMode: Text.Wrap
            lineHeight: 1.04
        }
        component Body: Text {
            width: parent.width
            color: Theme.dim
            font.family: Theme.sans
            font.pixelSize: 17
            wrapMode: Text.Wrap
            lineHeight: 1.22
        }

        readonly property real colW: Math.min(560, width - 120)
        readonly property real colX: (width - colW) / 2

        // 0: welcome
        Step {
            index: 0
            Column {
                x: side.colX; width: side.colW
                anchors.verticalCenter: parent.verticalCenter
                anchors.verticalCenterOffset: -30
                spacing: 22
                Title { text: "Let Claude use your computer" }
                Body { text: "SudoClaude lets Claude see your screen and work in any app the way you would, next to you, without taking over your mouse. It can use your phone too, and answer when you call it." }
                Column {
                    width: parent.width
                    spacing: 12
                    topPadding: 8
                    Repeater {
                        model: [{i: "desktop_windows", t: "Any app on your desktop, not just the browser"},
                                {i: "smartphone", t: "Your Android phone, over Wi-Fi"},
                                {i: "keyboard_alt", t: "Super + Space to ask, by typing or by voice"}]
                        Row {
                            required property var modelData
                            spacing: 14
                            Rectangle {
                                width: 36; height: 36; radius: 12
                                color: Theme.surface
                                Icon { anchors.centerIn: parent; name: parent.parent.modelData.i; size: 20; color: Theme.accent }
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: parent.modelData.t
                                color: Theme.text
                                font.family: Theme.sans
                                font.pixelSize: 15
                            }
                        }
                    }
                }
            }
        }

        // 1: check
        Step {
            index: 1
            Column {
                x: side.colX; width: side.colW
                anchors.verticalCenter: parent.verticalCenter
                anchors.verticalCenterOffset: -30
                spacing: 18
                Title { text: "First, a quick look around" }
                Body { text: page.checks.length === 0 ? "Checking your system…"
                           : page.ready ? "Everything SudoClaude needs is here."
                           : "Something SudoClaude needs is missing. Fix it, then check again." }
                Group {
                    Repeater {
                        model: page.checks
                        ListRow {
                            required property var modelData
                            icon: modelData.ok ? "check_circle" : modelData.required ? "error" : "info"
                            iconTone: modelData.ok ? Theme.goodSoft : modelData.required ? Theme.badSoft : Theme.surfaceHi
                            iconInk: modelData.ok ? Theme.good : modelData.required ? Theme.bad : Theme.dim
                            title: modelData.label
                            detail: modelData.detail
                            height: 62
                        }
                    }
                }
                Btn { kind: "text"; small: true; icon: "refresh"; text: "Check again"; onClicked: backend.checkRequirements() }
            }
        }

        // 2: choose
        Step {
            index: 2
            Flickable {
                anchors.fill: parent
                contentHeight: chooseCol.height + 160
                Column {
                    id: chooseCol
                    x: side.colX; width: side.colW
                    y: Math.max(40, (side.height - height) / 2 - 40)
                    spacing: 18
                    Title { text: "What should Claude be able to do?" }
                    Body { text: "You can change all of this later." }
                    Group {
                        ListRow {
                            icon: "desktop_windows"
                            title: "Use the desktop"
                            detail: "See the screen and use any app. This is the core of SudoClaude."
                            Switch { checked: true; active: false }
                        }
                        ListRow {
                            icon: "layers"
                            title: "Show itself on screen"
                            detail: page.has("quickshell") ? "The glass pill, its cursor and an edge light while it works."
                                                           : "Needs Quickshell, which isn't installed."
                            active: page.has("quickshell")
                            Switch { checked: page.optOverlay && page.has("quickshell"); active: page.has("quickshell")
                                     onToggled: x => page.optOverlay = x }
                        }
                        ListRow {
                            icon: "visibility"
                            title: "Read text in any app"
                            detail: "Installs Tesseract, for apps that don't expose their text."
                            Switch { checked: page.optOcr; onToggled: x => page.optOcr = x }
                        }
                        ListRow {
                            icon: "smartphone"
                            title: "Use my Android phone"
                            detail: "Installs adb and scrcpy. You pair the phone afterwards."
                            Switch { checked: page.optPhone; onToggled: x => page.optPhone = x }
                        }
                        ListRow {
                            icon: "graphic_eq"
                            title: "Voice"
                            detail: "Talk instead of type. Downloads about 3 GB of speech models and uses a few GB of memory while it runs."
                            Switch { checked: page.optVoice; onToggled: x => page.optVoice = x }
                        }
                        ListRow {
                            icon: "language"
                            title: "Work inside Chromium tabs"
                            detail: page.has("chromium") ? "A small extension for clicking and reading in background tabs."
                                                         : "Chromium isn't installed."
                            active: page.has("chromium")
                            Switch { checked: page.optBrowser && page.has("chromium"); active: page.has("chromium")
                                     onToggled: x => page.optBrowser = x }
                        }
                    }
                }
            }
        }

        // 3: keys
        Step {
            index: 3
            Column {
                x: side.colX; width: side.colW
                anchors.verticalCenter: parent.verticalCenter
                anchors.verticalCenterOffset: -30
                spacing: 18
                Title { text: "How will you call Claude?" }
                Body { text: "Click a shortcut and press the keys you want." }
                Group {
                    ListRow {
                        icon: "keyboard_alt"
                        title: "Talk or type"
                        KeyRecorder { combo: page.talk; onChanged: c => page.talk = c }
                    }
                    ListRow {
                        icon: "stop_circle"
                        title: "Stop"
                        KeyRecorder { combo: page.stopKey; onChanged: c => page.stopKey = c }
                    }
                }
            }
        }

        // 4: install
        Step {
            index: 4
            Column {
                x: side.colX; width: side.colW
                anchors.verticalCenter: parent.verticalCenter
                anchors.verticalCenterOffset: -30
                spacing: 20
                Title { text: "Setting things up" }
                Body { text: page.log.length ? page.log[page.log.length - 1] : "Starting…"; maximumLineCount: 2; elide: Text.ElideRight }
                Wave { width: parent.width; running: page.step === 4 }
                Btn { kind: "text"; small: true; icon: page.showLog ? "expand_more" : "chevron_right"
                      text: page.showLog ? "Hide details" : "Show details"; onClicked: page.showLog = !page.showLog }
                Rectangle {
                    width: parent.width
                    visible: page.showLog
                    height: 240
                    radius: 20
                    color: Theme.surfaceLow
                    Flickable {
                        anchors.fill: parent
                        anchors.margins: 16
                        contentHeight: logT.implicitHeight
                        contentY: Math.max(0, contentHeight - height)
                        clip: true
                        Text { id: logT; width: parent.width; text: page.log.join("\n"); color: Theme.dim
                               font.family: "monospace"; font.pixelSize: 12; wrapMode: Text.WrapAnywhere }
                    }
                }
            }
        }

        // 5: done
        Step {
            index: 5
            Column {
                x: side.colX; width: side.colW
                anchors.verticalCenter: parent.verticalCenter
                anchors.verticalCenterOffset: -30
                spacing: 20
                Blob {
                    width: 72; height: 72
                    lobes: 9; depth: 0.1
                    tone: page.failed ? Theme.badSoft : Theme.goodSoft
                    Icon { anchors.centerIn: parent; name: page.failed ? "error" : "check"; size: 36; weight: 600
                           color: page.failed ? Theme.bad : Theme.good }
                }
                Title { text: page.failed ? "That didn't finish" : "Claude's ready" }
                Body { text: page.failed ? "The details below say what went wrong. Fix it and try again."
                                         : "Press " + page.talk.replace(/\+/g, " + ") + " and ask for something. Or open a Claude Code session and tell it what to do on your computer." }
                Rectangle {
                    width: parent.width
                    visible: page.failed
                    height: 200
                    radius: 20
                    color: Theme.surfaceLow
                    Flickable {
                        anchors.fill: parent; anchors.margins: 16
                        contentHeight: failT.implicitHeight
                        contentY: Math.max(0, contentHeight - height)
                        clip: true
                        Text { id: failT; width: parent.width; text: page.log.slice(-60).join("\n"); color: Theme.dim
                               font.family: "monospace"; font.pixelSize: 12; wrapMode: Text.WrapAnywhere }
                    }
                }
            }
        }

    }
}
