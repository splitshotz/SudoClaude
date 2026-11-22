import QtQuick
import QtQuick.Window
import "."

Window {
    id: win
    width: 1200
    height: 800
    minimumWidth: 980
    minimumHeight: 660
    visible: true
    title: "SudoClaude"
    color: Theme.bg

    FontLoader { source: Qt.resolvedUrl("../../fonts/Newsreader.ttf") }
    FontLoader { source: Qt.resolvedUrl("../../fonts/GoogleSansFlex.ttf") }
    FontLoader { source: Qt.resolvedUrl("../../fonts/MaterialSymbolsRounded.ttf") }

    readonly property bool systemDark: Qt.styleHints.colorScheme !== Qt.ColorScheme.Light
    Binding { target: Theme; property: "dark"
              value: backend.theme === "dark" || (backend.theme === "system" && win.systemDark) }
    Binding { target: Theme; property: "frost"; value: { Theme.cfgRev; return backend.get("glass.frost") } }
    Binding { target: Theme; property: "lens"; value: { Theme.cfgRev; return backend.get("glass.lens") } }
    Binding { target: Theme; property: "tintMix"; value: { Theme.cfgRev; return backend.get("glass.tint") } }

    readonly property bool setup: !backend.installed || setupPage.holding
    property string tab: "overview"
    readonly property var pages: [
        {id: "overview", label: "Overview", icon: "space_dashboard"},
        {id: "computer", label: "Computer", icon: "desktop_windows"},
        {id: "phone", label: "Phone", icon: "smartphone"},
        {id: "assistant", label: "Assistant", icon: "graphic_eq"},
        {id: "appearance", label: "Appearance", icon: "palette"},
        {id: "keyboard", label: "Keyboard", icon: "keyboard"},
        {id: "updates", label: "Updates", icon: "system_update",
         badge: backend.updateAvailable || backend.appUpdateAvailable},
        {id: "about", label: "About", icon: "info"}]
    readonly property real sideW: 244
    readonly property real inset: sideW + 20

    Connections {
        target: backend
        function onConfigChanged() { Theme.cfgRev++ }
        function onToast(t) { toast.show(t) }
        function onTaskFinished(task, ok, msg) {
            if (task === "doctor") { doctorSheet.text = msg; doctorSheet.ok = ok; doctorSheet.busy = false }
            else if (task === "keybinds") toast.show(ok ? "Shortcuts saved" : "Couldn't save those shortcuts")
            else if (task === "uninstall") { uninstallSheet.open = false; toast.show(ok ? "SudoClaude was uninstalled" : msg) }
            else if (task === "phone-pair") toast.show(ok ? "Phone paired" : msg)
            else if (task === "phone-connect" && !ok) toast.show(msg)
        }
    }

    // ---- the content layer: everything the floating glass refracts ---------------
    Item {
        id: scene
        anchors.fill: parent

        Rectangle { anchors.fill: parent; color: Theme.bg }

        // One composed mark in the sidebar's empty middle, between the nav and
        // the status line: a scalloped shape with a smaller one set against its
        // upper right, under the glass so it bends them. It only shows when
        // there's room for it, and turns very slowly.
        Item {
            id: ambient
            readonly property real y0: 450
            readonly property real y1: parent.height - 100
            readonly property real d: Math.min(176, y1 - y0 - 30)
            x: 10
            y: y0 + (y1 - y0 - d) / 2 + 10
            width: win.sideW
            height: d
            opacity: win.setup || d < 120 ? 0 : 1
            Behavior on opacity { NumberAnimation { duration: 500 } }
            property real t: 0
            NumberAnimation on t { from: 0; to: Math.PI * 2; duration: 120000; loops: Animation.Infinite }
            Blob {
                width: ambient.d; height: ambient.d
                x: (parent.width - width) / 2 - ambient.d * 0.08
                y: 0
                lobes: 12; depth: 0.06
                spin: ambient.t
                tone: Theme.accentSoft
            }
            Blob {
                width: ambient.d * 0.42; height: width
                x: parent.width / 2 + ambient.d * 0.2
                y: -ambient.d * 0.12
                lobes: 4; depth: 0.15
                spin: -ambient.t * 2
                tone: Theme.dark ? "#2E2A3A" : "#E6E0F2"
            }
        }

        SetupPage {
            id: setupPage
            objectName: "setupPage"
            anchors.fill: parent
            visible: opacity > 0.01
            opacity: win.setup ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 450 } }
        }

        component Host: Item {
            id: host
            property string name
            readonly property bool on: !win.setup && win.tab === name
            property real t: on ? 1 : 0
            Behavior on t { NumberAnimation { duration: 380; easing.type: Easing.OutCubic } }
            anchors.fill: parent
            visible: t > 0.005
            opacity: t
            transform: Translate { y: (1 - host.t) * 18 }
        }

        Host { name: "overview"; OverviewPage { id: pOverview; anchors.fill: parent; leftInset: win.inset; onGo: p => win.tab = p } }
        Host { name: "computer"; ComputerPage { id: pComputer; anchors.fill: parent; leftInset: win.inset; onDoctor: win.runDoctor() } }
        Host { name: "phone"; PhonePage { id: pPhone; anchors.fill: parent; leftInset: win.inset } }
        Host { name: "assistant"; AssistantPage { id: pAssistant; anchors.fill: parent; leftInset: win.inset
                                                  onAskEnableVoice: voiceSheet.open = true } }
        Host { name: "appearance"; AppearancePage { id: pAppearance; anchors.fill: parent; leftInset: win.inset } }
        Host { name: "keyboard"; KeyboardPage { id: pKeyboard; anchors.fill: parent; leftInset: win.inset } }
        Host { name: "updates"; UpdatesPage { id: pUpdates; anchors.fill: parent; leftInset: win.inset } }
        Host { name: "about"; AboutPage { id: pAbout; anchors.fill: parent; leftInset: win.inset
                                          onAskUninstall: uninstallSheet.open = true } }
    }
    ShaderEffectSource {
        id: backdropTex
        sourceItem: scene
        live: true
        width: 0; height: 0
    }

    function runDoctor() {
        doctorSheet.text = ""
        doctorSheet.busy = true
        doctorSheet.open = true
        backend.doctor()
    }
    readonly property var current: ({ overview: pOverview, computer: pComputer, phone: pPhone, assistant: pAssistant,
                                      appearance: pAppearance, keyboard: pKeyboard, updates: pUpdates, about: pAbout })[tab]

    // ---- the floating layer ---------------------------------------------------------
    Sidebar {
        id: sidebar
        x: win.setup ? -win.sideW - 40 : 10
        Behavior on x { SpringAnimation { spring: 2.6; damping: 0.42 } }
        y: 10
        width: win.sideW
        height: parent.height - 20
        items: win.pages
        current: win.tab
        onPicked: id => win.tab = id
    }

    Toolbar {
        id: toolbar
        x: parent.width - 10 - width
        y: win.setup ? -70 : 10
        Behavior on y { SpringAnimation { spring: 2.6; damping: 0.42 } }
        IconBtn {
            visible: win.tab === "computer" || win.tab === "overview"
            icon: "health_and_safety"
            onClicked: win.runDoctor()
        }
        IconBtn {
            visible: win.tab === "updates"
            icon: "refresh"
            onClicked: backend.checkUpdates()
        }
        IconBtn {
            visible: win.tab === "phone"
            icon: "sync"
            spinning: backend.busy === "phone"
            onClicked: backend.refreshPhone()
        }
        IconBtn {
            visible: win.tab === "overview"
            icon: "refresh"
            onClicked: { backend.refresh(); backend.refreshPhone() }
        }
        IconBtn {
            icon: Theme.dark ? "light_mode" : "dark_mode"
            onClicked: backend.setTheme(Theme.dark ? "light" : "dark")
        }
    }

    SetupNav {
        setup: setupPage
        y: win.setup ? parent.height - 92 : parent.height + 40
        Behavior on y { SpringAnimation { spring: 2.6; damping: 0.45 } }
    }

    Toast {
        id: toast
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.horizontalCenterOffset: win.setup ? 0 : win.inset / 2
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 30
    }

    // ---- sheets -----------------------------------------------------------------------
    Sheet {
        id: doctorSheet
        property string text: ""
        property bool ok: true
        property bool busy: false
        title: "Health check"
        icon: "health_and_safety"
        cardWidth: 680
        onDismissed: open = false
        Wave { width: parent.width; visible: doctorSheet.busy; running: doctorSheet.busy && doctorSheet.open }
        Flickable {
            width: parent.width
            visible: !doctorSheet.busy
            height: Math.min(380, docText.implicitHeight)
            contentHeight: docText.implicitHeight
            clip: true
            Text {
                id: docText
                width: parent.width
                text: doctorSheet.text
                color: doctorSheet.ok ? Theme.text : Theme.bad
                font.family: "monospace"
                font.pixelSize: 12
                wrapMode: Text.WrapAnywhere
            }
        }
        Btn { text: "Done"; kind: "tonal"; onClicked: doctorSheet.open = false }
    }

    Sheet {
        id: voiceSheet
        title: "Turn on voice?"
        icon: "graphic_eq"
        cardWidth: 600
        onDismissed: open = false
        Repeater {
            model: [{i: "memory", t: "While it runs, the speech models use about 4–6 GB of memory, and the Natural voice about 3 GB of GPU memory."},
                    {i: "timer", t: "The first Super + Space after it's been off takes a few seconds while the models load."},
                    {i: "hearing", t: "“Claude” works as a wake word only while it's running."},
                    {i: "sports_esports", t: "It quits when a game starts and never loads during one; typing takes over."},
                    {i: "bolt", t: "It leaves after the “Leave after unused” time and gives the memory back."}]
            Row {
                required property var modelData
                width: parent.width
                spacing: 14
                Icon { name: parent.modelData.i; size: 22; color: Theme.accent }
                Text {
                    width: parent.width - 36
                    text: parent.modelData.t
                    color: Theme.text
                    font.family: Theme.sans
                    font.pixelSize: 15
                    wrapMode: Text.Wrap
                    lineHeight: 1.15
                }
            }
        }
        Row {
            spacing: 10
            topPadding: 6
            Btn { text: "Turn on voice"; icon: "graphic_eq"
                  onClicked: { backend.set("voice.enabled", true); voiceSheet.open = false } }
            Btn { text: "Keep typing"; kind: "text"; onClicked: voiceSheet.open = false }
        }
    }

    Sheet {
        id: uninstallSheet
        property bool purge: false
        title: "Uninstall SudoClaude?"
        icon: "delete"
        onDismissed: open = false
        Text {
            width: parent.width
            text: "Claude loses access to your desktop and phone, the voice stops, and the keybinds and browser flags SudoClaude added are removed. The source folder stays."
            color: Theme.text
            font.family: Theme.sans
            font.pixelSize: 15
            wrapMode: Text.Wrap
            lineHeight: 1.15
        }
        Row {
            spacing: 12
            Switch { checked: uninstallSheet.purge; onToggled: v => uninstallSheet.purge = v }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "Also delete settings and voice models"
                color: Theme.text
                font.family: Theme.sans
                font.pixelSize: 15
            }
        }
        Row {
            spacing: 10
            Btn {
                text: backend.busy === "uninstall" ? "Uninstalling…" : "Uninstall"
                kind: "danger"
                busy: backend.busy === "uninstall"
                active: backend.busy === ""
                onClicked: backend.uninstall(uninstallSheet.purge)
            }
            Btn { text: "Cancel"; kind: "text"; onClicked: uninstallSheet.open = false }
        }
    }

    FrameAnimation { running: true; onTriggered: Theme.tick++ }

    Component.onCompleted: {
        Theme.scene = scene
        Theme.backdrop = backdropTex
        backend.refresh()
        backend.refreshPhone()
        backend.checkRequirements()
        backend.checkUpdates()
    }
    Timer { interval: 8000; running: true; repeat: true; onTriggered: backend.refresh() }
}
