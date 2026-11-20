import QtQuick
import "."

// Versions, what's new, and updating SudoClaude and this app.
Item {
    id: page
    property bool shown: true
    property var log: []
    property string result: ""

    Connections {
        target: backend
        function onLogLine(line) {
            if (backend.busy !== "update" && backend.busy !== "app-update") return
            page.log = page.log.concat([line]).slice(-300)
        }
        function onTaskFinished(task, ok, msg) {
            if (task === "update") page.result = ok ? "Updated. The voice assistant and overlay restarted." : msg
            if (task === "app-update") page.result = msg
        }
    }

    Flickable {
        anchors.fill: parent
        contentHeight: col.height + 120
        boundsBehavior: Flickable.StopAtBounds
        clip: true

        Column {
            id: col
            width: Math.min(920, page.width - 96)
            anchors.horizontalCenter: parent.horizontalCenter
            topPadding: 118
            spacing: 24

            Headline {
                width: parent.width
                centered: false
                size: 92
                source: "what's *new*"
            }

            GlassCard {
                id: main
                width: parent.width
                height: mainCol.implicitHeight + 2 * padding
                delay: 60
                shown: page.shown
                padding: 32
                Column {
                    id: mainCol
                    width: main.width - 2 * main.padding
                    spacing: 14
                    Row {
                        width: parent.width
                        spacing: 18
                        Text {
                            text: backend.updateAvailable ? backend.latest.version : (backend.version || "–")
                            color: backend.updateAvailable ? Theme.accent : Theme.text
                            font.family: Theme.serif
                            font.pixelSize: 72
                        }
                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 4
                            Text {
                                text: backend.updateAvailable ? "A new version of SudoClaude is ready"
                                    : backend.latest.error ? "Couldn't reach GitHub"
                                    : backend.latest.version ? "SudoClaude is up to date" : "Checking…"
                                color: Theme.text
                                font.family: Theme.sans
                                font.pixelSize: 18
                                font.weight: Font.DemiBold
                            }
                            Text {
                                text: backend.updateAvailable ? "You have " + backend.version + "."
                                    : backend.latest.error ? backend.latest.error
                                    : backend.latest.checked ? "Checked at " + backend.latest.checked + "." : ""
                                color: Theme.dim
                                font.family: Theme.sans
                                font.pixelSize: 14
                            }
                        }
                    }
                    Text {
                        visible: (backend.latest.notes || "").length > 0
                        width: parent.width
                        text: backend.latest.notes || ""
                        textFormat: Text.MarkdownText
                        color: Theme.dim
                        font.family: Theme.sans
                        font.pixelSize: 15
                        wrapMode: Text.Wrap
                        lineHeight: 1.25
                        onLinkActivated: link => Qt.openUrlExternally(link)
                    }
                    Row {
                        spacing: 12
                        topPadding: 6
                        GlassButton {
                            visible: backend.updateAvailable
                            text: backend.busy === "update" ? "Updating…" : "Update now"
                            accent: true
                            enabled_: backend.busy === ""
                            onClicked: { page.log = []; page.result = ""; backend.update() }
                        }
                        GlassButton {
                            text: "Check again"
                            enabled_: backend.busy === ""
                            onClicked: backend.checkUpdates()
                        }
                        GlassButton {
                            text: "Release page"
                            onClicked: Qt.openUrlExternally(backend.latest.url || backend.repoUrl + "/releases")
                        }
                    }
                }
            }

            GlassCard {
                id: appCard
                width: parent.width
                height: appCol.implicitHeight + 2 * padding
                delay: 140
                shown: page.shown
                Column {
                    id: appCol
                    width: appCard.width - 2 * appCard.padding
                    spacing: 10
                    Text {
                        text: "This app"
                        color: Theme.text
                        font.family: Theme.serif
                        font.pixelSize: 34
                    }
                    Text {
                        width: parent.width
                        text: backend.appUpdateAvailable
                              ? "Version " + backend.latest.version + " of this app is available (you have " + backend.appVersion
                                + "). It can download and install it for you; reopen the app afterwards."
                              : "Version " + backend.appVersion + ", the latest."
                        color: backend.appUpdateAvailable ? Theme.text : Theme.dim
                        font.family: Theme.sans
                        font.pixelSize: 15
                        wrapMode: Text.Wrap
                    }
                    GlassButton {
                        visible: backend.appUpdateAvailable
                        text: backend.busy === "app-update" ? "Installing…" : "Download and install"
                        accent: true
                        enabled_: backend.busy === ""
                        onClicked: { page.log = []; page.result = ""; backend.updateApp() }
                    }
                }
            }

            GlassCard {
                id: logCard
                visible: page.log.length > 0 || page.result.length > 0
                width: parent.width
                height: 260
                shown: visible
                padding: 22
                Column {
                    width: logCard.width - 2 * logCard.padding
                    spacing: 8
                    Text {
                        visible: page.result.length > 0
                        text: page.result
                        color: Theme.text
                        font.family: Theme.sans
                        font.pixelSize: 15
                        font.weight: Font.Medium
                        width: parent.width
                        wrapMode: Text.Wrap
                    }
                    Flickable {
                        id: lf
                        width: parent.width
                        height: 170
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
    }
}
