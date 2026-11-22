import QtQuick
import "."

Page {
    id: page
    readonly property var st: backend.status || ({})
    readonly property string liveTalk: hypr(st.binds && st.binds.talk) || "SUPER+Space"
    readonly property string liveStop: hypr(st.binds && st.binds.stop) || "SUPER+SHIFT+Escape"
    property string talk: liveTalk
    property string stop: liveStop
    readonly property bool dirty: talk !== liveTalk || stop !== liveStop
    property string error: ""

    // hyprctl reports "Super+Shift+Escape"; Hyprland's config wants "SUPER+SHIFT+Escape".
    function hypr(c) {
        if (!c) return ""
        var p = c.split("+")
        return p.map((x, i) => i < p.length - 1 ? x.toUpperCase() : x).join("+")
    }
    onLiveTalkChanged: talk = liveTalk
    onLiveStopChanged: stop = liveStop

    title: "Keyboard"
    subtitle: page.st.hyprland === false ? "Shortcuts need Hyprland."
            : "Click a shortcut and press a new one. They're saved to your Hyprland keybinds, which get backed up first."

    Group {
        ListRow {
            icon: "keyboard_alt"
            title: "Talk or type to Claude"
            detail: "Press again to finish, or while Claude is answering to cut in."
            KeyRecorder { combo: page.talk; onChanged: c => { page.talk = c; page.error = "" } }
        }
        ListRow {
            icon: "stop_circle"
            title: "Stop Claude"
            detail: "Esc also works while the pill is showing."
            KeyRecorder { combo: page.stop; onChanged: c => { page.stop = c; page.error = "" } }
        }
    }

    Row {
        spacing: 10
        Btn {
            text: backend.busy === "keybinds" ? "Saving…" : "Save shortcuts"
            icon: "check"
            active: page.dirty && backend.busy === ""
            busy: backend.busy === "keybinds"
            onClicked: { page.error = ""; backend.setKeybinds(page.talk, page.stop) }
        }
        Btn {
            kind: "text"
            text: "Undo"
            visible: page.dirty
            onClicked: { page.talk = page.liveTalk; page.stop = page.liveStop; page.error = "" }
        }
    }
    Text {
        width: parent.width
        visible: page.error !== ""
        text: page.error
        color: Theme.bad
        font.family: Theme.sans
        font.pixelSize: 14
        wrapMode: Text.Wrap
    }

    Connections {
        target: backend
        function onTaskFinished(task, ok, msg) {
            if (task === "keybinds") page.error = ok ? "" : msg
        }
    }
}
