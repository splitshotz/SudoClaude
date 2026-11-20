import QtQuick
import QtQuick.Effects
import "."

// First run, one calm step at a time: welcome, a look around, what to install,
// keys, the install itself, done.
Item {
    id: page
    property bool shown: true

    // Steps: 0 welcome, 1 check, 2 choose, 3 keys, 4 install, 5 done
    property int step: 0
    readonly property int stepIndex: step
    property bool failed: false
    property bool dismissed: false
    readonly property bool holding: step >= 4 && !dismissed
    property var log: []
    property bool showLog: false

    property bool optOcr: true
    property bool optVoice: false
    property bool optBrowser: false
    property string talk: "SUPER+Space"
    property string stopKey: "SUPER+SHIFT+Escape"

    readonly property var checks: backend.checks || []
    readonly property bool ready: checks.length > 0 && checks.every(x => x.ok || !x.required)

    function next() {
        if (step === 2 && !optVoice) step = 4
        else step = Math.min(5, step + 1)
        if (step === 4) startInstall()
    }
    function back() {
        if (step === 4 && !optVoice) step = 2
        else step = Math.max(0, step - 1)
    }
    function startInstall() {
        log = []
        failed = false
        backend.install({ ocr: optOcr, voice: optVoice, browser: optBrowser, talk: talk, stop: stopKey })
    }

    Connections {
        target: backend
        function onLogLine(line) {
            if (backend.busy === "install") page.log = page.log.concat([line]).slice(-400)
        }
        function onTaskFinished(task, ok, msg) {
            if (task !== "install") return
            page.failed = !ok
            page.step = 5
        }
    }

    // One step on screen at a time. The leaving step drifts up and goes out of
    // focus; the next one rises into place and sharpens.
    // ---- 0: welcome ------------------------------------------------------------
    SetupStep {
        current: page.step
        index: 0
        Column {
            anchors.centerIn: parent
            anchors.verticalCenterOffset: -20
            width: Math.min(1100, page.width - 120)
            spacing: 30
            Headline { width: parent.width; source: "meet claude,\n*at home* on your desktop" }
            Text {
                width: parent.width * 0.62
                anchors.horizontalCenter: parent.horizontalCenter
                horizontalAlignment: Text.AlignHCenter
                text: "It sees your screen, uses any app the way you would, works next to you without taking your mouse, and talks back when you call it."
                color: Theme.dim
                font.family: Theme.sans
                font.pixelSize: 18
                wrapMode: Text.Wrap
                lineHeight: 1.3
            }
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 12
                topPadding: 6
                GlassButton { text: "Get started"; primary: true; implicitHeight: 48; onClicked: page.next() }
                GlassButton { text: "What is this?"; implicitHeight: 48; onClicked: Qt.openUrlExternally(backend.repoUrl) }
            }
        }
    }

    // ---- 1: a look around ---------------------------------------------------------
    SetupStep {
        current: page.step
        index: 1
        Column {
            anchors.centerIn: parent
            width: Math.min(900, page.width - 120)
            spacing: 34
            Headline { width: parent.width; size: 92; source: "first, a quick\n*look around*" }
            Column {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 520
                spacing: 2
                Repeater {
                    model: page.checks
                    Item {
                        id: row
                        required property var modelData
                        required property int index
                        width: 520
                        height: 46
                        // Each result settles in a beat after the one above it.
                        property real a: 0
                        Behavior on a { NumberAnimation { duration: 420; easing.type: Easing.OutCubic } }
                        Timer { running: page.step === 1; interval: 160 + row.index * 110; onTriggered: row.a = 1 }
                        Connections { target: page; function onStepChanged() { if (page.step !== 1) row.a = 0 } }
                        opacity: a
                        transform: Translate { x: (1 - row.a) * 14 }
                        Text {
                            id: mark
                            anchors.verticalCenter: parent.verticalCenter
                            width: 28
                            text: row.modelData.ok ? "✓" : row.modelData.required ? "✕" : "–"
                            color: row.modelData.ok ? Theme.accentText : row.modelData.required ? Theme.bad : Theme.dim
                            font.pixelSize: 17
                            font.weight: Font.Bold
                        }
                        Text {
                            anchors.left: mark.right
                            anchors.verticalCenter: parent.verticalCenter
                            text: row.modelData.label
                            color: Theme.text
                            font.family: Theme.sans
                            font.pixelSize: 17
                            font.weight: Font.Medium
                        }
                        Text {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            width: 260
                            horizontalAlignment: Text.AlignRight
                            text: row.modelData.required || row.modelData.ok ? row.modelData.detail
                                                                             : "optional · " + row.modelData.detail
                            color: Theme.dim
                            font.family: Theme.sans
                            font.pixelSize: 14
                            elide: Text.ElideRight
                        }
                        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.faint }
                    }
                }
                Text {
                    visible: page.checks.length === 0
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Looking…"
                    color: Theme.dim
                    font.family: Theme.sans
                    font.pixelSize: 16
                }
            }
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 12
                GlassButton { text: "Back"; implicitHeight: 48; onClicked: page.back() }
                GlassButton { text: page.ready ? "Looks good" : "Fix the ✕ items first"; primary: true
                              arrow: page.ready; enabled_: page.ready; implicitHeight: 48; onClicked: page.next() }
                GlassButton { visible: !page.ready; text: "Check again"; implicitHeight: 48
                              onClicked: backend.checkRequirements() }
            }
        }
    }

    // ---- 2: what to install ---------------------------------------------------------
    SetupStep {
        current: page.step
        index: 2
        Column {
            anchors.centerIn: parent
            width: Math.min(1060, page.width - 120)
            spacing: 34
            Headline { width: parent.width; size: 92; source: "what should claude\n*be able to do?*" }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Seeing and using your desktop is always included. Pick any extras."
                color: Theme.dim
                font.family: Theme.sans
                font.pixelSize: 17
            }
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 18
                Tile { title: "Voice"; picked: page.optVoice; onToggle: page.optVoice = !page.optVoice
                       body: "Say “Claude” and talk, or type to it. Downloads about 2 GB of speech models." }
                Tile { title: "Reading text"; picked: page.optOcr; onToggle: page.optOcr = !page.optOcr
                       body: "OCR, for apps that don't expose their buttons and labels." }
                Tile { title: "Chromium tabs"; picked: page.optBrowser; onToggle: page.optBrowser = !page.optBrowser
                       body: "An extension so Claude can work inside Chromium tabs directly." }
            }
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 12
                GlassButton { text: "Back"; implicitHeight: 48; onClicked: page.back() }
                GlassButton { text: page.optVoice ? "Continue" : "Install"; primary: true; implicitHeight: 48
                              onClicked: page.next() }
            }
        }
    }

    // ---- 3: keys ----------------------------------------------------------------------
    SetupStep {
        current: page.step
        index: 3
        Column {
            anchors.centerIn: parent
            width: Math.min(900, page.width - 120)
            spacing: 36
            Headline { width: parent.width; size: 92; source: "how will you\n*call* claude?" }
            Text {
                width: parent.width * 0.7
                anchors.horizontalCenter: parent.horizontalCenter
                horizontalAlignment: Text.AlignHCenter
                text: "Say “Claude” any time. These keys work too, and press talk again to cut in while it's speaking. They're only added if nothing else uses them."
                color: Theme.dim
                font.family: Theme.sans
                font.pixelSize: 17
                wrapMode: Text.Wrap
                lineHeight: 1.3
            }
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 40
                Repeater {
                    model: [{label: "talk", key: "talk"}, {label: "stop", key: "stopKey"}]
                    Column {
                        required property var modelData
                        spacing: 12
                        Row {
                            anchors.horizontalCenter: parent.horizontalCenter
                            spacing: 8
                            Repeater {
                                model: page[modelData.key].split("+")
                                Item {
                                    id: cap
                                    required property string modelData
                                    width: Math.max(56, capText.implicitWidth + 30); height: 56
                                    GlassSurface { target: cap; radius: 14; band: 8; margin: 12 }
                                    Text {
                                        id: capText
                                        anchors.centerIn: parent
                                        text: cap.modelData.charAt(0) + cap.modelData.slice(1).toLowerCase()
                                        color: Theme.text
                                        font.family: Theme.sans
                                        font.pixelSize: 17
                                        font.weight: Font.DemiBold
                                    }
                                }
                            }
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: modelData.label
                            color: Theme.dim
                            font.family: Theme.serif
                            font.italic: true
                            font.pixelSize: 22
                        }
                        GField {
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: 230
                            text: page[modelData.key]
                            onEdited: t => page[modelData.key] = t.replace(/ /g, "").toUpperCase()
                        }
                    }
                }
            }
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 12
                GlassButton { text: "Back"; implicitHeight: 48; onClicked: page.back() }
                GlassButton { text: "Install"; primary: true; implicitHeight: 48; onClicked: page.next() }
            }
        }
    }

    // ---- 4: installing -------------------------------------------------------------------
    SetupStep {
        current: page.step
        index: 4
        Column {
            anchors.centerIn: parent
            width: Math.min(900, page.width - 120)
            spacing: 30
            Headline { width: parent.width; size: 92; source: "setting things *up*" }
            Item {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 420; height: 3
                clip: true
                Rectangle { anchors.fill: parent; radius: 1.5; color: Theme.faint }
                Rectangle {
                    id: sweep
                    height: parent.height; radius: 1.5
                    width: 140
                    color: Theme.accentText
                    SequentialAnimation on x {
                        running: page.step === 4
                        loops: Animation.Infinite
                        NumberAnimation { from: -140; to: 420; duration: 1500; easing.type: Easing.InOutCubic }
                    }
                }
            }
            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: page.log.length ? page.log[page.log.length - 1] : "Starting…"
                color: Theme.dim
                font.family: Theme.sans
                font.pixelSize: 15
                elide: Text.ElideMiddle
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: page.optVoice ? "The voice models are big, so this can take a few minutes. You may be asked for your password."
                                    : "You may be asked for your password."
                color: Theme.dim
                opacity: 0.8
                font.family: Theme.sans
                font.pixelSize: 14
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: page.showLog ? "Hide details" : "Show details"
                color: detailsArea.containsMouse ? Theme.accentText : Theme.dim
                font.family: Theme.sans
                font.pixelSize: 14
                font.underline: true
                MouseArea { id: detailsArea; anchors.fill: parent; hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor; onClicked: page.showLog = !page.showLog }
            }
            GlassCard {
                id: logCard
                visible: page.showLog
                shown: page.showLog
                anchors.horizontalCenter: parent.horizontalCenter
                width: Math.min(820, parent.width)
                height: 240
                padding: 20
                radius: 22
                Flickable {
                    id: lf
                    width: logCard.width - 2 * logCard.padding
                    height: logCard.height - 2 * logCard.padding
                    contentHeight: lt.implicitHeight
                    contentY: Math.max(0, contentHeight - height)
                    clip: true
                    Text {
                        id: lt
                        width: lf.width
                        text: page.log.join("\n")
                        color: Theme.dim
                        font.family: "monospace"
                        font.pixelSize: 12
                        wrapMode: Text.WrapAnywhere
                    }
                }
            }
        }
    }

    // ---- 5: done -------------------------------------------------------------------------
    SetupStep {
        current: page.step
        index: 5
        Column {
            anchors.centerIn: parent
            width: Math.min(1000, page.width - 120)
            spacing: 30
            Headline { width: parent.width; source: page.failed ? "that didn't\n*quite* finish" : "you're\n*all set*" }
            Text {
                width: parent.width * 0.62
                anchors.horizontalCenter: parent.horizontalCenter
                horizontalAlignment: Text.AlignHCenter
                text: page.failed
                      ? "The details below say what went wrong. Fixing it and installing again is safe."
                      : page.optVoice ? "Say “Claude”, or open a new Claude session and ask it to do something on your computer."
                                      : "Open a new Claude session and ask it to do something on your computer."
                color: Theme.dim
                font.family: Theme.sans
                font.pixelSize: 18
                wrapMode: Text.Wrap
                lineHeight: 1.3
            }
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 12
                GlassButton { visible: !page.failed; text: "Open SudoClaude"; primary: true; implicitHeight: 48
                              onClicked: { page.dismissed = true; backend.refresh() } }
                GlassButton { visible: page.failed; text: "Try again"; primary: true; implicitHeight: 48
                              onClicked: { page.step = 4; page.startInstall() } }
                GlassButton { visible: page.failed; text: "Show details"; implicitHeight: 48
                              onClicked: { page.showLog = true; page.step = 4 } }
            }
        }
    }

    // Progress dots.
    Row {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 40
        spacing: 8
        Repeater {
            model: 6
            Rectangle {
                required property int index
                width: index === page.step ? 22 : 6
                height: 6
                radius: 3
                color: index === page.step ? Theme.accentText : Theme.rgba(Theme.text, index < page.step ? 0.45 : 0.18)
                Behavior on width { SpringAnimation { spring: 4; damping: 0.45 } }
                Behavior on color { ColorAnimation { duration: 250 } }
            }
        }
    }
}
