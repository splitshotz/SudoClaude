import QtQuick
import "."

Page {
    id: page
    signal askEnableVoice()
    function v(path) { Theme.cfgRev; return backend.get(path) }
    readonly property var st: backend.status || ({})
    readonly property bool voice: v("voice.enabled") === true
    title: "Assistant"
    subtitle: "What happens when you press " + ((st.binds && st.binds.talk) || "Super+Space").replace(/\+/g, " + ") + "."

    // Typing or voice, as two big choices.
    Row {
        width: parent.width
        spacing: 12
        Repeater {
            model: [{id: false, icon: "keyboard_alt", title: "Typing",
                     detail: "A box to type to Claude. Loads nothing heavy, works in games."},
                    {id: true, icon: "graphic_eq", title: "Voice",
                     detail: "Talk and hear answers. Uses a few GB of memory while it runs."}]
            Item {
                id: choice
                required property var modelData
                readonly property bool on: page.voice === modelData.id
                width: (parent.width - 12) / 2
                height: 132
                Rectangle {
                    anchors.fill: parent
                    radius: choice.on ? 32 : 22
                    Behavior on radius { SpringAnimation { spring: 4; damping: 0.42 } }
                    color: choice.on ? Theme.accentSoft : Theme.surface
                    border.width: choice.on ? 0 : 1
                    border.color: Theme.line
                    Behavior on color { ColorAnimation { duration: 200 } }
                }
                Icon {
                    x: 22; y: 22
                    name: choice.modelData.icon
                    size: 28
                    fill: choice.on ? 1 : 0
                    color: choice.on ? Theme.accentInk : Theme.text
                }
                Rectangle {
                    anchors.right: parent.right; anchors.rightMargin: 20
                    y: 22
                    width: 24; height: 24; radius: 12
                    color: choice.on ? Theme.accentFill : "transparent"
                    border.width: choice.on ? 0 : 2
                    border.color: Theme.rgba(Theme.text, 0.3)
                    Icon { anchors.centerIn: parent; visible: choice.on; name: "check"; size: 16; weight: 700; color: Theme.inkOnAccent }
                }
                Column {
                    x: 22
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 20
                    width: parent.width - 44
                    spacing: 3
                    Text { text: choice.modelData.title; color: choice.on ? Theme.accentInk : Theme.text
                           font.family: Theme.sans; font.pixelSize: 17; font.weight: Font.DemiBold }
                    Text { width: parent.width; text: choice.modelData.detail; wrapMode: Text.Wrap
                           color: choice.on ? Theme.rgba(Theme.accentInk, 0.8) : Theme.dim
                           font.family: Theme.sans; font.pixelSize: 13 }
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (choice.on) return
                        if (choice.modelData.id) page.askEnableVoice()
                        else backend.set("voice.enabled", false)
                    }
                }
            }
        }
    }

    Group {
        title: "Claude"
        ListRow {
            icon: "person"
            title: "What Claude calls you"
            detail: "Leave empty to use the first name on your account."
            Field { width: 200; text: page.v("voice.name") || ""; placeholder: backend.userName || "Your name"
                    onEdited: t => backend.set("voice.name", t.trim()) }
        }
        ListRow {
            icon: "chat"
            title: "Everyday model"
            detail: "Quick questions and simple tasks."
            Segmented {
                options: [{value: "haiku", label: "Haiku"}, {value: "sonnet", label: "Sonnet"}, {value: "opus", label: "Opus"}]
                value: page.v("voice.model")
                onPicked: x => backend.set("voice.model", x)
            }
        }
        ListRow {
            icon: "psychology"
            title: "For harder work"
            detail: "Coding, Blender, Unity, and anything you ask Opus for."
            Segmented {
                options: [{value: "sonnet", label: "Sonnet"}, {value: "opus", label: "Opus"}]
                value: page.v("voice.deep_model")
                onPicked: x => backend.set("voice.deep_model", x)
            }
        }
    }

    Group {
        title: "Voice"
        opacity: page.voice ? 1 : 0.5
        Behavior on opacity { NumberAnimation { duration: 200 } }
        ListRow {
            icon: "music_note"
            title: "Voice"
            detail: "Natural runs on an NVIDIA GPU. Light runs on the CPU, and is used in games either way."
            Segmented {
                options: [{value: "chatterbox", label: "Natural"}, {value: "kokoro", label: "Light"}]
                value: page.v("voice.tts")
                onPicked: x => backend.set("voice.tts", x)
            }
        }
        ListRow {
            icon: "hearing"
            title: "Wake word sensitivity"
            detail: "Higher hears “Claude” from further away, and wakes by mistake more often."
            Slider { width: 280; from: 0; to: 1; step: 0.05; decimals: 2
                     format: x => Math.round(x * 100) + "%"
                     value: (0.8 - page.v("voice.wake_threshold")) / 0.45
                     onMoved: x => backend.set("voice.wake_threshold", Math.round((0.8 - x * 0.45) * 100) / 100) }
        }
        ListRow {
            icon: "chat"
            title: "Keep listening after answering"
            detail: "So you can reply without saying its name."
            Slider { width: 280; from: 2; to: 15; step: 0.5; suffix: " s"
                     value: page.v("voice.followup_seconds"); onMoved: x => backend.set("voice.followup_seconds", x) }
        }
        ListRow {
            icon: "volume_down"
            title: "Other audio while talking"
            Slider { width: 280; from: 0; to: 100; step: 5; decimals: 0; suffix: "%"
                     value: page.v("voice.duck") * 100; onMoved: x => backend.set("voice.duck", Math.round(x) / 100) }
        }
        ListRow {
            icon: "notifications"
            title: "Chime when it wakes"
            Switch { checked: page.v("voice.chime"); onToggled: x => backend.set("voice.chime", x) }
        }
        ListRow {
            icon: "front_hand"
            title: "Interrupt by voice"
            detail: "Talking over Claude cuts it off. Super+Space always does."
            Switch { checked: page.v("voice.voice_interrupt"); onToggled: x => backend.set("voice.voice_interrupt", x) }
        }
        ListRow {
            icon: "timer"
            title: "Leave after unused"
            detail: "Quits and gives its memory back. 0 keeps it running."
            Slider { width: 280; from: 0; to: 120; step: 5; decimals: 0; suffix: " min"
                     value: page.v("voice.idle_exit_minutes")
                     onMoved: x => backend.set("voice.idle_exit_minutes", Math.round(x)) }
        }
    }

    Group {
        title: "Stepping aside"
        opacity: page.voice ? 1 : 0.5
        ListRow {
            icon: "sports_esports"
            title: "When a game starts"
            detail: "The voice turns off and typing takes over until the game closes."
            Switch { checked: page.v("voice.pause_for_games"); onToggled: x => backend.set("voice.pause_for_games", x) }
        }
        ListRow {
            icon: "memory"
            title: "When memory gets tight"
            detail: "Below " + page.v("voice.low_memory_gb") + " GB free, the voice hands its memory back."
            Switch { checked: page.v("voice.pause_on_low_memory"); onToggled: x => backend.set("voice.pause_on_low_memory", x) }
        }
        ListRow {
            icon: "tune"
            title: "Tight means less than"
            active: page.v("voice.pause_on_low_memory") === true
            Slider { width: 280; from: 1; to: 12; step: 0.5; suffix: " GB"; active: parent.parent.active
                     value: page.v("voice.low_memory_gb"); onMoved: x => backend.set("voice.low_memory_gb", x) }
        }
    }

    SectionReset { section: "voice" }
}
