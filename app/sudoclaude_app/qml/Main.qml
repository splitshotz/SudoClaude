import QtQuick
import QtQuick.Window
import QtQuick.Effects
import "."

Window {
    id: win
    width: 1280
    height: 860
    minimumWidth: 1000
    minimumHeight: 700
    visible: true
    title: "SudoClaude"
    color: Theme.base

    FontLoader { source: Qt.resolvedUrl("../../fonts/InstrumentSerif-Regular.ttf") }
    FontLoader { source: Qt.resolvedUrl("../../fonts/InstrumentSerif-Italic.ttf") }
    FontLoader { source: Qt.resolvedUrl("../../fonts/InterVariable.ttf") }

    // Theme follows the system unless the user picked one.
    readonly property bool systemDark: Qt.styleHints.colorScheme !== Qt.ColorScheme.Light
    Binding { target: Theme; property: "dark"
              value: backend.theme === "dark" || (backend.theme === "system" && win.systemDark) }
    Binding { target: Theme; property: "frost"; value: { Theme.cfgRev; return backend.get("glass.frost") } }
    Binding { target: Theme; property: "lens"; value: { Theme.cfgRev; return backend.get("glass.lens") } }
    Binding { target: Theme; property: "tintMix"; value: { Theme.cfgRev; return backend.get("glass.tint") } }
    Connections {
        target: backend
        function onConfigChanged() { Theme.cfgRev++ }
        function onToast(t) { toast.show(t) }
        function onTaskFinished(task, ok, msg) {
            if (task === "doctor") { doctorSheet.text = msg; doctorSheet.ok = ok; doctorSheet.open = true }
            else if (task === "keybinds") toast.show(ok ? "Keys updated" : "Couldn't set those keys")
            else if (task === "uninstall") { uninstallSheet.open = false; toast.show(ok ? "SudoClaude was uninstalled" : msg) }
        }
    }

    // ---- the scene everything refracts -------------------------------------------
    Item {
        id: scene
        anchors.fill: parent

        ShaderEffect {
            id: backdrop
            anchors.fill: parent
            property size size: Qt.size(width, height)
            property real time: 0
            property real dark: Theme.dark ? 1 : 0
            Behavior on dark { NumberAnimation { duration: 600; easing.type: Easing.InOutQuad } }
            property real hue: scene.setup ? setupPage.stepIndex / 5 : 0.4
            Behavior on hue { NumberAnimation { duration: 1400; easing.type: Easing.InOutCubic } }
            // Warm charcoal or paper, with Claude's orange as the light in it.
            property color k1: Theme.dark ? "#141010" : "#F6F1EA"
            property color k2: Theme.dark ? "#231915" : "#EFE4D9"
            property color k3: Theme.dark ? "#C9502A" : "#F4A27C"
            Behavior on k1 { ColorAnimation { duration: 700 } }
            Behavior on k2 { ColorAnimation { duration: 700 } }
            Behavior on k3 { ColorAnimation { duration: 700 } }
            property vector4d c1: Qt.vector4d(k1.r, k1.g, k1.b, 1)
            property vector4d c2: Qt.vector4d(k2.r, k2.g, k2.b, 1)
            property vector4d c3: Qt.vector4d(k3.r, k3.g, k3.b, 1)
            NumberAnimation on time { from: 0; to: 100000; duration: 100000000; loops: Animation.Infinite }
            fragmentShader: Qt.resolvedUrl("shaders/backdrop.frag.qsb")
        }
        ShaderEffectSource {
            id: backdropTex
            width: 0; height: 0
            sourceItem: backdrop
            live: true
        }

        // ---- pages --------------------------------------------------------------
        readonly property bool setup: !backend.installed || setupPage.holding
        property string tab: "home"
        readonly property string current: setup ? "setup" : tab

        component PageHost: Item {
            id: host
            property string name
            readonly property bool on: scene.current === name
            property real t: on ? 1 : 0
            Behavior on t { NumberAnimation { duration: 520; easing.type: Easing.OutCubic } }
            anchors.fill: parent
            visible: t > 0.002
            opacity: t
            scale: 0.97 + 0.03 * t
            // Pages blur into and out of focus as they swap.
            layer.enabled: visible
            layer.effect: MultiEffect {
                blurEnabled: true
                blurMax: 48
                blur: 1 - host.t
            }
        }

        PageHost { name: "setup"; SetupPage { id: setupPage; objectName: "setupPage"; anchors.fill: parent; shown: parent.on } }
        PageHost { name: "home"; HomePage { anchors.fill: parent; shown: parent.on
                                            onOpenUpdates: scene.tab = "updates"
                                            onShowDoctor: { doctorSheet.text = "Checking…"; doctorSheet.ok = true; doctorSheet.open = true; backend.doctor() } } }
        PageHost { name: "settings"; SettingsPage { anchors.fill: parent; shown: parent.on
                                                    onAskUninstall: uninstallSheet.open = true } }
        PageHost { name: "updates"; UpdatesPage { anchors.fill: parent; shown: parent.on } }

        // ---- chrome -------------------------------------------------------------
        Text {
            x: 36
            y: 30
            text: "SudoClaude"
            color: Theme.text
            opacity: scene.setup ? 0 : 1
            Behavior on opacity { NumberAnimation { duration: 400 } }
            font.family: Theme.serif
            font.italic: true
            font.pixelSize: 30
        }
        TabBar {
            anchors.horizontalCenter: parent.horizontalCenter
            y: scene.setup ? -80 : 24
            Behavior on y { SpringAnimation { spring: 3; damping: 0.45 } }
            tabs: [{id: "home", label: "Home"}, {id: "settings", label: "Settings"},
                   {id: "updates", label: backend.updateAvailable || backend.appUpdateAvailable ? "Updates  •" : "Updates"}]
            current: scene.tab
            onPicked: id => scene.tab = id
        }

        Toast {
            id: toast
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 34
        }

        Sheet {
            id: doctorSheet
            property string text: ""
            property bool ok: true
            title: "Health check"
            cardWidth: 680
            onDismissed: open = false
            Flickable {
                width: parent.width
                height: Math.min(420, docText.implicitHeight)
                contentHeight: docText.implicitHeight
                clip: true
                Text {
                    id: docText
                    width: parent.width
                    text: doctorSheet.text
                    color: doctorSheet.ok ? Theme.dim : Theme.bad
                    font.family: "monospace"
                    font.pixelSize: 12
                    wrapMode: Text.WrapAnywhere
                }
            }
            GlassButton { text: "Close"; onClicked: doctorSheet.open = false }
        }

        Sheet {
            id: uninstallSheet
            property bool purge: false
            title: "Uninstall SudoClaude?"
            onDismissed: open = false
            Text {
                width: parent.width
                text: "Claude loses access to your desktop, the voice assistant stops, and the keybinds and browser flags it added are removed. The source folder stays."
                color: Theme.dim
                font.family: Theme.sans
                font.pixelSize: 15
                wrapMode: Text.Wrap
                lineHeight: 1.2
            }
            SettingRow {
                title: "Also delete settings and voice models"
                GToggle { checked: uninstallSheet.purge; onToggled: v => uninstallSheet.purge = v }
            }
            Row {
                spacing: 12
                GlassButton {
                    text: backend.busy === "uninstall" ? "Uninstalling…" : "Uninstall"
                    danger: true
                    enabled_: backend.busy === ""
                    onClicked: backend.uninstall(uninstallSheet.purge)
                }
                GlassButton { text: "Cancel"; onClicked: uninstallSheet.open = false }
            }
        }
    }

    // Glass follows things as they scroll and animate.
    FrameAnimation { running: true; onTriggered: Theme.tick++ }

    Component.onCompleted: {
        Theme.scene = scene
        Theme.backdrop = backdropTex
        backend.refresh()
        backend.checkRequirements()
        backend.checkUpdates()
    }
    Timer { interval: 8000; running: true; repeat: true; onTriggered: backend.refresh() }
}
