import QtQuick
import "."

// Dashboard: a greeting, how each part is doing, recent conversation, version.
Item {
    id: page
    property bool shown: true
    signal openUpdates()
    signal showDoctor()

    readonly property var st: backend.status || ({})
    readonly property string greeting: {
        const h = new Date().getHours()
        const part = h < 5 ? "still up" : h < 12 ? "good morning" : h < 18 ? "good afternoon" : "good evening"
        return backend.userName ? part + ", *" + backend.userName.toLowerCase() + "*." : "*" + part + "*."
    }
    readonly property string talkKey: (st.binds && st.binds.talk) ? st.binds.talk : ""

    Flickable {
        anchors.fill: parent
        contentHeight: col.height + 100
        boundsBehavior: Flickable.StopAtBounds
        clip: true

        Column {
            id: col
            width: Math.min(1060, page.width - 96)
            anchors.horizontalCenter: parent.horizontalCenter
            topPadding: 118
            spacing: 24

            Headline {
                width: parent.width
                centered: false
                size: 92
                source: page.greeting
            }
            Text {
                width: parent.width * 0.8
                text: page.st.voice_active
                      ? "Claude is listening for its name" + (page.talkKey ? ", or press " + page.talkKey.replace(/\+/g, " + ") : "")
                        + ". Ask it to use anything on your desktop."
                      : "Claude can see and use your desktop from any Claude session. Ask it to do something on your computer."
                color: Theme.dim
                font.family: Theme.sans
                font.pixelSize: 19
                wrapMode: Text.Wrap
                lineHeight: 1.25
            }

            Row {
                width: parent.width
                spacing: 20
                readonly property real w: (width - 40) / 3

                StatusCard {
                    width: parent.w
                    delay: 60
                    shown: page.shown
                    label: "Computer use"
                    headline: page.st.claude_code || page.st.claude_desktop ? "Connected" : "Not connected"
                    tone: page.st.claude_code || page.st.claude_desktop ? "good" : "bad"
                    detail: page.st.claude_code && page.st.claude_desktop ? "Available in Claude Code and the Claude app."
                          : page.st.claude_code ? "Available in Claude Code."
                          : page.st.claude_desktop ? "Available in the Claude app."
                          : "Run setup again to register it with Claude."
                    action: "Health check"
                    onAct: page.showDoctor()
                }
                StatusCard {
                    width: parent.w
                    delay: 130
                    shown: page.shown
                    label: "Voice"
                    headline: !page.st.voice_installed ? "Not set up" : page.st.voice_active ? "Listening"
                            : page.st.voice_paused ? "Taking a break" : "Stopped"
                    tone: !page.st.voice_installed ? "off" : page.st.voice_active ? "good" : page.st.voice_paused ? "off" : "warn"
                    detail: !page.st.voice_installed ? "Install the voice assistant from Settings to talk to Claude."
                          : page.st.voice_active ? (page.st.wake_trained ? "Wake word trained on your voice." : "Using the built-in wake word.")
                          : page.st.voice_paused ? "Off while " + page.st.voice_paused + ". It comes back on its own."
                          : "The voice service isn't running."
                    action: !page.st.voice_installed ? "" : page.st.voice_paused ? "Turn on now" : "Restart"
                    onAct: backend.restartVoice()
                }
                StatusCard {
                    width: parent.w
                    delay: 200
                    shown: page.shown
                    label: "Overlay"
                    headline: !page.st.quickshell ? "Unavailable" : page.st.overlay_running ? "Running" : "Ready"
                    tone: !page.st.quickshell ? "warn" : "good"
                    detail: !page.st.quickshell ? "Install Quickshell to see the glass pill and Claude's cursor."
                          : page.st.overlay_running ? "The glass pill and Claude's cursor are up."
                          : "It appears when Claude works or listens."
                    action: page.st.quickshell ? "Restart" : ""
                    onAct: backend.restartOverlay()
                }
            }

            Row {
                width: parent.width
                spacing: 20

                GlassCard {
                    id: act
                    width: (parent.width - 20) * 0.64
                    height: Math.max(260, actCol.implicitHeight + 2 * padding)
                    delay: 260
                    shown: page.shown
                    Column {
                        id: actCol
                        width: act.width - 2 * act.padding
                        spacing: 12
                        Text {
                            text: "Lately"
                            color: Theme.text
                            font.family: Theme.serif
                            font.pixelSize: 34
                        }
                        Repeater {
                            model: page.st.activity || []
                            Row {
                                required property var modelData
                                width: actCol.width
                                spacing: 14
                                Text {
                                    width: 44
                                    text: modelData.time
                                    color: Theme.dim
                                    font.family: Theme.sans
                                    font.pixelSize: 13
                                    topPadding: 2
                                }
                                Text {
                                    width: parent.width - 58
                                    text: modelData.text
                                    color: modelData.who === "claude" ? Theme.text : Theme.dim
                                    font.family: modelData.who === "claude" ? Theme.serif : Theme.sans
                                    font.pixelSize: modelData.who === "claude" ? 19 : 15
                                    font.italic: modelData.who === "you"
                                    wrapMode: Text.Wrap
                                    maximumLineCount: 2
                                    elide: Text.ElideRight
                                }
                            }
                        }
                        Text {
                            visible: !(page.st.activity || []).length
                            text: "Nothing yet today. Say “Claude” to start."
                            color: Theme.dim
                            font.family: Theme.sans
                            font.pixelSize: 15
                        }
                    }
                }

                GlassCard {
                    id: ver
                    width: (parent.width - 20) * 0.36
                    height: act.height
                    delay: 320
                    shown: page.shown
                    Column {
                        width: ver.width - 2 * ver.padding
                        spacing: 8
                        Text {
                            text: "VERSION"
                            color: Theme.dim
                            font.family: Theme.sans
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                            font.letterSpacing: 1.4
                        }
                        Text {
                            text: backend.version || "–"
                            color: Theme.text
                            font.family: Theme.serif
                            font.pixelSize: 64
                        }
                        Text {
                            width: parent.width
                            text: backend.updateAvailable ? backend.latest.version + " is out."
                                : backend.latest.version ? "You're up to date." : "Checking for updates…"
                            color: backend.updateAvailable ? Theme.accent : Theme.dim
                            font.family: Theme.sans
                            font.pixelSize: 15
                            font.weight: backend.updateAvailable ? Font.DemiBold : Font.Normal
                            wrapMode: Text.Wrap
                        }
                    }
                    GlassButton {
                        anchors.left: parent.left
                        anchors.bottom: parent.bottom
                        text: backend.updateAvailable ? "See what's new" : "Updates"
                        accent: backend.updateAvailable
                        onClicked: page.openUpdates()
                    }
                }
            }
        }
    }
}
