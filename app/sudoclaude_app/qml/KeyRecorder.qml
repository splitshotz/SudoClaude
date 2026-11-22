import QtQuick
import "."

// Shows a shortcut as keycaps; click it and press a new one. Hyprland's own binds
// are paused while recording (backend.recordKeys) so combos like Super+Space reach
// the app. Escape on its own cancels.
Item {
    id: k
    property string combo: ""          // Hyprland form, e.g. "SUPER+SHIFT+Escape"
    property bool recording: false
    property var held: []               // modifiers currently down while recording
    signal changed(string combo)
    width: Math.max(220, caps.implicitWidth + 32)
    height: 48

    readonly property var names: ({ "SUPER": "Super", "SHIFT": "Shift", "CTRL": "Ctrl", "ALT": "Alt" })
    function parts(c) { return (c || "").split("+").filter(x => x.length) }
    function pretty(p) { return names[p.toUpperCase()] || (p.length === 1 ? p.toUpperCase() : p) }

    function start() {
        recording = true
        held = []
        backend.recordKeys(true)
        catcher.forceActiveFocus()
    }
    function stop() {
        if (!recording) return
        recording = false
        held = []
        backend.recordKeys(false)
    }

    function mods(m) {
        var out = []
        if (m & Qt.MetaModifier) out.push("SUPER")
        if (m & Qt.ControlModifier) out.push("CTRL")
        if (m & Qt.AltModifier) out.push("ALT")
        if (m & Qt.ShiftModifier) out.push("SHIFT")
        return out
    }
    function keyName(e) {
        var key = e.key
        if (key >= Qt.Key_A && key <= Qt.Key_Z) return String.fromCharCode(key)
        if (key >= Qt.Key_0 && key <= Qt.Key_9) return String.fromCharCode(key)
        if (key >= Qt.Key_F1 && key <= Qt.Key_F24) return "F" + (key - Qt.Key_F1 + 1)
        var map = {}
        map[Qt.Key_Space] = "Space"; map[Qt.Key_Escape] = "Escape"; map[Qt.Key_Return] = "Return"
        map[Qt.Key_Enter] = "Return"; map[Qt.Key_Tab] = "Tab"; map[Qt.Key_Backspace] = "BackSpace"
        map[Qt.Key_Delete] = "Delete"; map[Qt.Key_Insert] = "Insert"; map[Qt.Key_Home] = "Home"
        map[Qt.Key_End] = "End"; map[Qt.Key_PageUp] = "Prior"; map[Qt.Key_PageDown] = "Next"
        map[Qt.Key_Left] = "Left"; map[Qt.Key_Right] = "Right"; map[Qt.Key_Up] = "Up"
        map[Qt.Key_Down] = "Down"; map[Qt.Key_Slash] = "slash"; map[Qt.Key_Backslash] = "backslash"
        map[Qt.Key_Comma] = "comma"; map[Qt.Key_Period] = "period"; map[Qt.Key_Semicolon] = "semicolon"
        map[Qt.Key_Apostrophe] = "apostrophe"; map[Qt.Key_BracketLeft] = "bracketleft"
        map[Qt.Key_BracketRight] = "bracketright"; map[Qt.Key_Minus] = "minus"; map[Qt.Key_Equal] = "equal"
        map[Qt.Key_QuoteLeft] = "grave"; map[Qt.Key_Print] = "Print"; map[Qt.Key_Pause] = "Pause"
        return map[key] || ""
    }

    Item {
        id: catcher
        focus: k.recording
        Keys.onPressed: e => {
            if (!k.recording) return
            e.accepted = true
            var m = k.mods(e.modifiers)
            var name = k.keyName(e)
            if (!name) { k.held = m; return }           // a modifier on its own: show it, keep waiting
            if (name === "Escape" && m.length === 0) { k.stop(); return }
            if (m.length === 0 && !/^F\d+$/.test(name)) { k.held = []; return }   // needs a modifier
            var c = m.concat([name]).join("+")
            k.stop()
            if (c !== k.combo) k.changed(c)
        }
        Keys.onReleased: e => { if (k.recording) { e.accepted = true; k.held = k.mods(e.modifiers) } }
        onActiveFocusChanged: if (!activeFocus) k.stop()
    }

    Rectangle {
        anchors.fill: parent
        radius: 16
        color: k.recording ? Theme.accentSoft : Theme.surfaceHi
        border.width: k.recording ? 2 : 0
        border.color: Theme.accentFill
        Behavior on color { ColorAnimation { duration: 160 } }
        SequentialAnimation on opacity {
            running: k.recording
            loops: Animation.Infinite
            NumberAnimation { to: 0.75; duration: 700; easing.type: Easing.InOutSine }
            NumberAnimation { to: 1; duration: 700; easing.type: Easing.InOutSine }
            onRunningChanged: if (!running) parent.opacity = 1
        }
    }
    Row {
        id: caps
        anchors.centerIn: parent
        spacing: 6
        Repeater {
            model: k.recording ? k.held.concat(k.held.length ? [] : []) : k.parts(k.combo)
            Rectangle {
                required property string modelData
                height: 30
                width: Math.max(30, capText.implicitWidth + 18)
                radius: 8
                color: Theme.surface
                border.width: 1
                border.color: Theme.line
                Rectangle {   // the key's lower lip
                    anchors.bottom: parent.bottom
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: parent.width - 2
                    height: 3
                    radius: 2
                    color: Theme.rgba(Theme.text, 0.10)
                }
                Text {
                    id: capText
                    anchors.centerIn: parent
                    anchors.verticalCenterOffset: -1
                    text: k.pretty(parent.modelData)
                    color: Theme.text
                    font.family: Theme.sans
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                }
            }
        }
        Text {
            visible: k.recording
            anchors.verticalCenter: parent.verticalCenter
            text: k.held.length ? "+ …" : "Press the new shortcut"
            color: Theme.accentInk
            font.family: Theme.sans
            font.pixelSize: 14
            font.weight: Font.Medium
        }
    }
    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: k.recording ? k.stop() : k.start()
    }
    Component.onDestruction: stop()
}
