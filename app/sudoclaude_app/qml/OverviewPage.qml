import QtQuick
import "."

Page {
    id: page
    signal go(string page)
    readonly property var st: backend.status || ({})
    readonly property var ph: backend.phone || ({})
    function v(path) { Theme.cfgRev; return backend.get(path) }
    readonly property string greeting: {
        var h = new Date().getHours()
        var part = h < 5 ? "Good evening" : h < 12 ? "Good morning" : h < 18 ? "Good afternoon" : "Good evening"
        return backend.userName ? part + ", " + backend.userName : part
    }
    title: greeting
    subtitle: "Here's what Claude can reach from this computer."

    Grid {
        width: parent.width
        columns: 2
        columnSpacing: 12
        rowSpacing: 12
        readonly property real cw: (width - columnSpacing) / 2

        Tile {
            width: parent.cw
            icon: "desktop_windows"
            lobes: 12
            title: "Computer"
            chip: page.st.installed ? "Ready" : "Not set up"
            chipTone: page.st.installed ? "good" : "warn"
            detail: page.st.claude_code && page.st.claude_desktop ? "Available in Claude Code and the Claude app."
                  : page.st.claude_code ? "Available in Claude Code." : page.st.claude_desktop ? "Available in the Claude app."
                  : "Run setup to connect Claude."
            onClicked: page.go("computer")
        }
        Tile {
            width: parent.cw
            icon: "smartphone"
            lobes: 4
            tone: Theme.dark ? "#2A3326" : "#E3EEDD"
            ink: Theme.dark ? "#C6E3B5" : "#2E4A22"
            title: "Phone"
            chip: page.ph.connected ? (page.ph.battery || "Connected") : page.ph.paired ? "Away" : "Not paired"
            chipTone: page.ph.connected ? "good" : "neutral"
            detail: page.ph.connected ? (page.ph.name ? page.ph.name + " · " : "") + (page.ph.device || "").replace(/ \(.*\)$/, "")
                  : page.ph.paired ? "Turn on Wireless debugging and it reconnects."
                  : "Pair an Android phone so Claude can use it too."
            onClicked: page.go("phone")
        }
        Tile {
            width: parent.cw
            icon: page.v("voice.enabled") ? "graphic_eq" : "keyboard_alt"
            lobes: 6
            tone: Theme.dark ? "#2E2A3A" : "#E8E3F3"
            ink: Theme.dark ? "#D8CCF5" : "#3B2E63"
            title: page.v("voice.enabled") ? "Voice" : "Typing"
            chip: page.st.voice_active ? "Listening" : page.st.voice_paused ? "Paused" : ""
            chipTone: "accent"
            detail: (page.st.binds && page.st.binds.talk ? page.st.binds.talk.replace(/\+/g, " + ") : "Super + Space")
                    + (page.v("voice.enabled") ? " to talk, or say “Claude” while it's running." : " opens a box to type to Claude.")
            onClicked: page.go("assistant")
        }
        Tile {
            width: parent.cw
            icon: "layers"
            lobes: 9
            tone: Theme.dark ? "#23313A" : "#DDEBF2"
            ink: Theme.dark ? "#BFE0F0" : "#1F4559"
            title: "Overlay"
            chip: page.v("overlay") === false ? "Off" : page.st.quickshell ? "" : "Needs Quickshell"
            chipTone: page.v("overlay") === false ? "neutral" : "warn"
            detail: page.v("overlay") === false ? "Claude works without showing anything on screen."
                  : "The glass pill, Claude's cursor and the edge light while it works."
            onClicked: page.go("appearance")
        }
    }

    Group {
        title: "Lately"
        visible: (page.st.activity || []).length > 0
        Repeater {
            model: page.st.activity || []
            ListRow {
                required property var modelData
                icon: modelData.who === "you" ? "person" : "arrow_selector_tool"
                iconTone: modelData.who === "you" ? Theme.surfaceHi : Theme.accentSoft
                iconInk: modelData.who === "you" ? Theme.text : Theme.accentInk
                title: modelData.text
                detail: (modelData.who === "you" ? "You" : "Claude") + " · " + modelData.time
            }
        }
    }

    Group {
        ListRow {
            icon: "system_update"
            title: backend.updateAvailable ? "SudoClaude " + backend.latest.version + " is out" : "Up to date"
            detail: "SudoClaude " + (backend.version || "?") + " · App " + backend.appVersion
            clickable: true
            chevron: true
            onClicked: page.go("updates")
        }
    }
}
