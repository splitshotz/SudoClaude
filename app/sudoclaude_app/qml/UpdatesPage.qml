import QtQuick
import "."

Page {
    id: page
    property var log: []
    property string result: ""
    property bool resultOk: true
    readonly property var latest: backend.latest || ({})
    title: "Updates"
    subtitle: latest.checked ? "Last checked at " + latest.checked + "." : "Checking GitHub for new releases…"

    Connections {
        target: backend
        function onLogLine(line) {
            if (backend.busy !== "update" && backend.busy !== "app-update") return
            page.log = page.log.concat([line]).slice(-300)
        }
        function onTaskFinished(task, ok, msg) {
            if (task !== "update" && task !== "app-update") return
            page.resultOk = ok
            page.result = task === "update" ? (ok ? "Updated. The voice and the overlay restarted." : msg) : msg
        }
    }

    // ---- SudoClaude ---------------------------------------------------------------
    Rectangle {
        width: parent.width
        height: top.implicitHeight + 56
        radius: 32
        color: backend.updateAvailable ? Theme.accentSoft : Theme.surface
        Column {
            id: top
            x: 28; y: 28
            width: parent.width - 56
            spacing: 14
            Row {
                spacing: 14
                Blob {
                    width: 52; height: 52
                    lobes: 12
                    depth: 0.07
                    tone: backend.updateAvailable ? Theme.accentFill : Theme.surfaceHi
                    Icon { anchors.centerIn: parent; name: backend.updateAvailable ? "download" : "task_alt"
                           size: 26; fill: 1; color: backend.updateAvailable ? Theme.inkOnAccent : Theme.good }
                }
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2
                    Text {
                        text: backend.updateAvailable ? "SudoClaude " + page.latest.version + " is ready"
                                                      : "SudoClaude is up to date"
                        color: backend.updateAvailable ? Theme.accentInk : Theme.text
                        font.family: Theme.serif
                        font.pixelSize: 26
                        font.variableAxes: ({ "opsz": 36, "wght": 450 })
                    }
                    Text {
                        text: "You have " + (backend.version || "?") + (page.latest.version ? " · latest is " + page.latest.version : "")
                        color: backend.updateAvailable ? Theme.rgba(Theme.accentInk, 0.75) : Theme.dim
                        font.family: Theme.sans
                        font.pixelSize: 14
                    }
                }
            }
            Text {
                width: parent.width
                visible: backend.updateAvailable && !!page.latest.notes
                text: page.latest.notes || ""
                textFormat: Text.MarkdownText
                color: Theme.accentInk
                font.family: Theme.sans
                font.pixelSize: 14
                wrapMode: Text.Wrap
                onLinkActivated: l => Qt.openUrlExternally(l)
            }
            Row {
                spacing: 10
                Btn {
                    visible: backend.updateAvailable
                    icon: "download"
                    text: backend.busy === "update" ? "Updating…" : "Update now"
                    busy: backend.busy === "update"
                    active: backend.busy === ""
                    onClicked: { page.log = []; page.result = ""; backend.update() }
                }
                Btn {
                    kind: backend.updateAvailable ? "text" : "tonal"
                    small: !backend.updateAvailable
                    icon: "refresh"
                    text: "Check again"
                    onClicked: backend.checkUpdates()
                }
                Btn {
                    kind: "text"
                    small: true
                    visible: !!page.latest.url
                    icon: "open_in_new"
                    text: "Release notes"
                    onClicked: Qt.openUrlExternally(page.latest.url)
                }
            }
        }
    }

    // ---- the app ------------------------------------------------------------------
    Group {
        title: "This app"
        ListRow {
            icon: backend.appUpdateAvailable ? "system_update" : "check_circle"
            iconTone: backend.appUpdateAvailable ? Theme.accentSoft : Theme.goodSoft
            iconInk: backend.appUpdateAvailable ? Theme.accentInk : Theme.good
            title: backend.appUpdateAvailable ? "App " + page.latest.version + " is available" : "App " + backend.appVersion
            detail: backend.appUpdateAvailable ? "Downloads the new Flatpak and installs it. Reopen the app afterwards."
                                               : "This is the newest version of the app."
            Btn {
                visible: backend.appUpdateAvailable
                kind: "tonal"; small: true
                text: backend.busy === "app-update" ? "Installing…" : "Install"
                busy: backend.busy === "app-update"
                active: backend.busy === ""
                onClicked: { page.log = []; page.result = ""; backend.updateApp() }
            }
        }
    }

    Text {
        width: parent.width
        visible: page.result !== ""
        text: page.result
        color: page.resultOk ? Theme.good : Theme.bad
        font.family: Theme.sans
        font.pixelSize: 14
        wrapMode: Text.Wrap
    }

    Rectangle {
        width: parent.width
        visible: page.log.length > 0
        height: Math.min(260, logText.implicitHeight + 32)
        radius: 20
        color: Theme.surfaceLow
        Flickable {
            anchors.fill: parent
            anchors.margins: 16
            contentHeight: logText.implicitHeight
            contentY: Math.max(0, contentHeight - height)
            clip: true
            Text {
                id: logText
                width: parent.width
                text: page.log.join("\n")
                color: Theme.dim
                font.family: "monospace"
                font.pixelSize: 12
                wrapMode: Text.WrapAnywhere
            }
        }
    }
}
