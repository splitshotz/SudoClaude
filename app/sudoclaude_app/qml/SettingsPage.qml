import QtQuick
import "."

// Every setting, grouped, each group with its own reset.
Item {
    id: page
    property bool shown: true
    signal askUninstall()
    signal askEnableVoice()

    function v(path) { Theme.cfgRev; return backend.get(path) }
    readonly property var st: backend.status || ({})

    Flickable {
        id: flick
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
                source: "your *settings*"
            }

            // ---- appearance ---------------------------------------------------
            SectionCard {
                title: "Appearance"
                subtitle: "How Claude shows up on your screen. Changes apply live."
                section: "appearance"
                delay: 60
                shown: page.shown

                // Live sample of the glass with the current settings.
                Item {
                    width: parent.width
                    height: 112
                    Item {
                        id: sample
                        width: 330; height: 50
                        anchors.centerIn: parent
                        GlassSurface { target: sample; radius: 25; band: 10 * Theme.lens }
                        Row {
                            anchors.centerIn: parent
                            spacing: 10
                            Rectangle { width: 14; height: 14; radius: 7; color: Theme.accent; anchors.verticalCenter: parent.verticalCenter }
                            Text { text: "Listening"; color: Theme.text; font.family: Theme.sans; font.pixelSize: 15; font.weight: Font.Medium }
                            Text { text: "what's the weather"; color: Theme.dim; font.family: Theme.sans; font.pixelSize: 15 }
                        }
                    }
                }
                SettingRow {
                    title: "On-screen overlay"
                    detail: "The glass pill, Claude's cursor and the edge light while it works."
                    GToggle { checked: page.v("overlay"); onToggled: x => backend.set("overlay", x) }
                }
                SettingRow {
                    title: "Edge style"
                    detail: "What marks the screen while Claude is working."
                    GSegmented {
                        options: [{value: "hairline", label: "Hairline"}, {value: "brackets", label: "Brackets"},
                                  {value: "spotlight", label: "Spotlight"}, {value: "minimal", label: "Minimal"},
                                  {value: "glow", label: "Glow"}]
                        value: page.v("overlay_style")
                        onPicked: x => backend.set("overlay_style", x)
                    }
                }
                SettingRow {
                    title: "Frost"
                    detail: "How much the glass blurs what's behind it."
                    GSlider { width: 300; from: 0; to: 12; step: 0.5; value: page.v("glass.frost"); suffix: " px"
                              onMoved: x => backend.set("glass.frost", x) }
                }
                SettingRow {
                    title: "Refraction"
                    detail: "How strongly the edges bend the content under them."
                    GSlider { width: 300; from: 0; to: 2; step: 0.05; decimals: 2; value: page.v("glass.lens")
                              onMoved: x => backend.set("glass.lens", x) }
                }
                SettingRow {
                    title: "Tint"
                    detail: "How much of the glass's own color shows through."
                    GSlider { width: 300; from: 0; to: 0.4; step: 0.01; decimals: 2; value: page.v("glass.tint")
                              onMoved: x => backend.set("glass.tint", x) }
                }
                SettingRow {
                    title: "Glass"
                    detail: "Automatic goes light over bright windows and dark over dark ones."
                    GSegmented {
                        options: [{value: "auto", label: "Automatic"}, {value: "light", label: "Light"},
                                  {value: "dark", label: "Dark"}]
                        value: page.v("glass.appearance")
                        onPicked: x => backend.set("glass.appearance", x)
                    }
                }
                SettingRow {
                    title: "Pill position"
                    detail: "Where the pill rests. You can also drag or flick it there."
                    Grid {
                        id: pos
                        columns: 3
                        spacing: 6
                        property string at: { Theme.cfgRev; return backend.pillPosition() }
                        Repeater {
                            model: ["top-left", "top", "top-right", "left", "", "right",
                                    "bottom-left", "bottom", "bottom-right"]
                            Item {
                                required property string modelData
                                width: 34; height: 22
                                Rectangle {
                                    anchors.centerIn: parent
                                    visible: modelData.length
                                    width: pos.at === modelData ? 26 : 14
                                    height: pos.at === modelData ? 10 : 6
                                    radius: height / 2
                                    color: pos.at === modelData ? Theme.accent : Theme.rgba(Theme.text, 0.25)
                                    Behavior on width { SpringAnimation { spring: 5; damping: 0.45 } }
                                    Behavior on color { ColorAnimation { duration: 150 } }
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    enabled: modelData.length
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: backend.setPillPosition(modelData)
                                }
                            }
                        }
                    }
                }
            }

            // ---- voice ----------------------------------------------------------
            SectionCard {
                title: "Voice"
                subtitle: page.st.voice_installed ? "The voice assistant restarts by itself when you change these."
                                                  : "The voice assistant isn't installed. Run setup again to add it."
                section: "voice"
                delay: 120
                shown: page.shown

                SettingRow {
                    title: "Voice mode"
                    detail: page.v("voice.enabled")
                            ? "Super+Space starts the voice; it leaves when unused or when a game starts."
                            : "Off: Super+Space opens Claude for typing, which loads nothing heavy."
                    // Turning it on goes through a sheet that explains the cost first.
                    GToggle { checked: page.v("voice.enabled") === true
                              onToggled: x => x ? page.askEnableVoice() : backend.set("voice.enabled", false) }
                }
                SettingRow {
                    title: "Leave after unused"
                    detail: "The voice quits after this long without being used, giving its memory back. 0 keeps it running."
                    GSlider { width: 300; from: 0; to: 120; step: 5; decimals: 0; suffix: " min"
                              value: page.v("voice.idle_exit_minutes")
                              onMoved: x => backend.set("voice.idle_exit_minutes", Math.round(x)) }
                }
                SettingRow {
                    title: "What Claude calls you"
                    detail: "Leave empty to use the first name on your account."
                    GField { width: 220; text: page.v("voice.name") || ""; placeholder: backend.userName || "Your name"
                             onEdited: t => backend.set("voice.name", t.trim()) }
                }
                SettingRow {
                    title: "Voice"
                    detail: "Natural runs on an NVIDIA GPU. Light runs on the CPU and is used during games either way."
                    GSegmented {
                        options: [{value: "chatterbox", label: "Natural"}, {value: "kokoro", label: "Light"}]
                        value: page.v("voice.tts")
                        onPicked: x => backend.set("voice.tts", x)
                    }
                }
                SettingRow {
                    title: "Wake word sensitivity"
                    detail: "Higher hears you from further away but wakes more often by mistake."
                    // Stored as the detector's threshold; sensitivity is the inverse.
                    GSlider { width: 300; from: 0; to: 1; step: 0.05; decimals: 2
                              value: (0.8 - page.v("voice.wake_threshold")) / 0.45
                              onMoved: x => backend.set("voice.wake_threshold", Math.round((0.8 - x * 0.45) * 100) / 100) }
                }
                SettingRow {
                    title: "Follow-up window"
                    detail: "How long it keeps listening after answering, so you can reply without its name."
                    GSlider { width: 300; from: 2; to: 15; step: 0.5; value: page.v("voice.followup_seconds"); suffix: " s"
                              onMoved: x => backend.set("voice.followup_seconds", x) }
                }
                SettingRow {
                    title: "Music volume while talking"
                    detail: "Other audio is turned down to this while you talk to Claude."
                    GSlider { width: 300; from: 0; to: 100; step: 5; decimals: 0
                              value: page.v("voice.duck") * 100; suffix: "%"
                              onMoved: x => backend.set("voice.duck", Math.round(x) / 100) }
                }
                SettingRow {
                    title: "Chime when it wakes"
                    detail: ""
                    GToggle { checked: page.v("voice.chime"); onToggled: x => backend.set("voice.chime", x) }
                }
                SettingRow {
                    title: "Interrupt by voice"
                    detail: "Saying its name or talking over it cuts it off. Off by default; Super+Space always works."
                    GToggle { checked: page.v("voice.voice_interrupt"); onToggled: x => backend.set("voice.voice_interrupt", x) }
                }
                SettingRow {
                    title: "Step aside for games"
                    detail: "Turns the voice off while a Steam game runs, then brings it back."
                    GToggle { checked: page.v("voice.pause_for_games"); onToggled: x => backend.set("voice.pause_for_games", x) }
                }
                SettingRow {
                    title: "Step aside when memory is tight"
                    detail: "The voice models hold a few GB of RAM. This hands it back when you need it."
                    GToggle { checked: page.v("voice.pause_on_low_memory"); onToggled: x => backend.set("voice.pause_on_low_memory", x) }
                }
                SettingRow {
                    title: "Tight means less than"
                    detail: "Free memory that counts as running low."
                    enabled: page.v("voice.pause_on_low_memory")
                    opacity: enabled ? 1 : 0.45
                    GSlider { width: 300; from: 1; to: 12; step: 0.5; value: page.v("voice.low_memory_gb"); suffix: " GB"
                              onMoved: x => backend.set("voice.low_memory_gb", x) }
                }
                SettingRow {
                    title: "Everyday model"
                    detail: "For quick questions and simple tasks."
                    GSegmented {
                        options: [{value: "haiku", label: "Haiku"}, {value: "sonnet", label: "Sonnet"}, {value: "opus", label: "Opus"}]
                        value: page.v("voice.model")
                        onPicked: x => backend.set("voice.model", x)
                    }
                }
                SettingRow {
                    title: "Model for hard tasks"
                    detail: "Coding, Blender, Unity and anything you ask Opus for."
                    GSegmented {
                        options: [{value: "sonnet", label: "Sonnet"}, {value: "opus", label: "Opus"}]
                        value: page.v("voice.deep_model")
                        onPicked: x => backend.set("voice.deep_model", x)
                    }
                }
            }

            // ---- computer use --------------------------------------------------
            SectionCard {
                title: "Computer use"
                subtitle: "How Claude works on your desktop. Applies to new Claude sessions."
                section: "computer"
                delay: 180
                shown: page.shown

                SettingRow {
                    title: "Ask before using apps"
                    detail: "Smart asks only for sensitive apps like password managers. Strict asks for every app. Off never asks."
                    GSegmented {
                        options: [{value: "smart", label: "Smart"}, {value: "strict", label: "Strict"}, {value: "off", label: "Off"}]
                        value: page.v("approvals")
                        onPicked: x => backend.set("approvals", x)
                    }
                }
                SettingRow {
                    title: "Work next to me"
                    detail: "Claude opens things beside you and borrows the mouse only when your hand is still."
                    GToggle { checked: page.v("copilot"); onToggled: x => backend.set("copilot", x) }
                }
                SettingRow {
                    title: "Escape stops Claude"
                    detail: ""
                    GToggle { checked: page.v("esc_to_stop"); onToggled: x => backend.set("esc_to_stop", x) }
                }
                SettingRow {
                    title: "Hide unapproved apps in screenshots"
                    detail: "Windows Claude hasn't been allowed to use are blanked out before it sees them."
                    GToggle { checked: page.v("mask_unapproved"); onToggled: x => backend.set("mask_unapproved", x) }
                }
                SettingRow {
                    title: "Notifications"
                    detail: "Start and stop popups when the overlay isn't available."
                    GToggle { checked: page.v("notifications") !== false; onToggled: x => backend.set("notifications", x) }
                }
                SettingRow {
                    title: "Hand control back after"
                    detail: "Seconds of inactivity before Claude lets go of the desktop."
                    GSlider { width: 300; from: 10; to: 120; step: 5; decimals: 0; value: page.v("idle_seconds"); suffix: " s"
                              onMoved: x => backend.set("idle_seconds", Math.round(x)) }
                }
                SettingRow {
                    title: "Remember approvals for"
                    detail: "How long a yes for an app lasts."
                    GSlider { width: 300; from: 10; to: 240; step: 10; decimals: 0; value: page.v("session_minutes"); suffix: " min"
                              onMoved: x => backend.set("session_minutes", Math.round(x)) }
                }
            }

            // ---- keybinds ------------------------------------------------------
            SectionCard {
                title: "Keys"
                subtitle: page.st.hyprland ? "Hyprland binds for the voice assistant." : "Needs Hyprland."
                delay: 240
                shown: page.shown
                SettingRow {
                    title: "Talk to Claude"
                    detail: "Press again to finish, or while Claude is talking to cut in."
                    GField { id: talkField; width: 220; text: (page.st.binds && page.st.binds.talk) || "SUPER+Space" }
                }
                SettingRow {
                    title: "Stop Claude"
                    detail: ""
                    GField { id: stopField; width: 220; text: (page.st.binds && page.st.binds.stop) || "SUPER+SHIFT+Escape" }
                }
                Item {
                    width: parent.width
                    height: 70
                    GlassButton {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Apply keys"
                        onClicked: backend.setKeybinds(talkField.text.replace(/ /g, "").toUpperCase(),
                                                       stopField.text.replace(/ /g, "").toUpperCase())
                    }
                }
            }

            // ---- app -------------------------------------------------------------
            SectionCard {
                title: "This app"
                delay: 300
                shown: page.shown
                SettingRow {
                    title: "Appearance"
                    detail: ""
                    GSegmented {
                        options: [{value: "system", label: "System"}, {value: "light", label: "Light"}, {value: "dark", label: "Dark"}]
                        value: backend.theme
                        onPicked: x => backend.setTheme(x)
                    }
                }
                SettingRow {
                    title: "Installed in"
                    detail: backend.repoPath
                    Item { width: 1; height: 1 }
                }
                Item {
                    width: parent.width
                    height: 76
                    GlassButton {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Uninstall SudoClaude"
                        danger: true
                        onClicked: page.askUninstall()
                    }
                }
            }
        }
    }
}
