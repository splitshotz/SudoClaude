import QtQuick
import "."

Page {
    id: page
    function v(path) { Theme.cfgRev; return backend.get(path) }
    readonly property var ph: backend.phone || ({})
    readonly property bool loading: ph.adb === undefined && !ph.error
    readonly property bool connected: !!ph.connected
    title: "Phone"
    subtitle: "Claude can use your Android phone over Wi-Fi: see the screen, tap, type and open apps."

    // ---- the phone itself -------------------------------------------------------
    Rectangle {
        width: parent.width
        height: 196
        radius: 32
        color: page.connected ? (Theme.dark ? "#22301F" : "#E6F0DF") : Theme.surface
        Behavior on color { ColorAnimation { duration: 300 } }

        Item {
            x: 28
            anchors.verticalCenter: parent.verticalCenter
            width: 92; height: 92
            Blob {
                anchors.fill: parent
                lobes: 4
                depth: 0.13
                tone: page.connected ? (Theme.dark ? "#355230" : "#C9E2BC") : Theme.surfaceHi
                RotationAnimator on rotation { running: page.loading; from: 0; to: 360; duration: 6000; loops: Animation.Infinite }
            }
            Icon {
                anchors.centerIn: parent
                name: page.connected ? "phone_android" : "mobile_off"
                size: 40
                fill: 1
                color: page.connected ? (Theme.dark ? "#CFEABF" : "#28451C") : Theme.dim
            }
        }
        Column {
            x: 146
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - x - 28
            spacing: 10
            Text {
                width: parent.width
                text: page.loading ? "Looking for your phone…"
                    : !page.ph.adb ? "adb isn't installed"
                    : page.connected ? (page.ph.name || (page.ph.device || "").replace(/ \(.*\)$/, ""))
                    : page.ph.paired ? "Your phone isn't reachable" : "No phone paired yet"
                color: Theme.text
                font.family: Theme.serif
                font.pixelSize: 28
                font.variableAxes: ({ "opsz": 40, "wght": 450 })
                wrapMode: Text.Wrap
            }
            Text {
                visible: page.connected && !!page.ph.name
                text: (page.ph.device || "").replace(/ \(.*\)$/, "")
                color: Theme.dim
                font.family: Theme.sans
                font.pixelSize: 14
            }
            Flow {
                width: parent.width
                spacing: 6
                visible: page.connected
                Chip { text: "Connected"; icon: "wifi"; tone: "good" }
                Chip { text: (page.ph.battery || "?") + (page.ph.charging ? " · charging" : "")
                       icon: page.ph.charging ? "battery_charging_full" : "battery_full" }
                Chip { text: page.ph.locked ? "Locked" : "Unlocked"; icon: page.ph.locked ? "lock" : "lock_open" }
            }
            Text {
                width: parent.width
                visible: !page.connected && !page.loading
                text: !page.ph.adb ? "Install android-tools (sudo pacman -S android-tools), or Android Studio's platform-tools."
                    : page.ph.paired ? "Make sure it's on the same Wi-Fi and Wireless debugging is on. It reconnects by itself."
                    : "Pair it once below. After that it connects by itself whenever Wireless debugging is on."
                color: Theme.dim
                font.family: Theme.sans
                font.pixelSize: 14
                wrapMode: Text.Wrap
                lineHeight: 1.15
            }
            Row {
                spacing: 8
                Btn {
                    visible: page.connected
                    kind: "tonal"; small: true; icon: "cast"; text: "Mirror screen"
                    active: !!page.ph.scrcpy
                    onClicked: backend.mirrorPhone()
                }
                Btn {
                    visible: page.ph.adb === true
                    kind: page.connected ? "text" : "tonal"; small: true; icon: "sync"
                    text: page.connected ? "Refresh" : "Try again"
                    busy: backend.busy === "phone"
                    onClicked: page.connected ? backend.refreshPhone() : backend.connectPhone()
                }
            }
        }
    }

    // ---- pairing ------------------------------------------------------------------
    Group {
        title: "Pair a phone"
        visible: page.ph.adb === true && !page.connected
        ListRow {
            icon: "settings"
            title: "1.  Turn on Wireless debugging"
            detail: "Settings → Developer options → Wireless debugging. No Developer options? Tap Build number seven times in About phone."
        }
        ListRow {
            icon: "link"
            title: "2.  Tap “Pair device with pairing code”"
            detail: "Keep that screen open. The phone needs to be on the same Wi-Fi as this computer."
        }
        Item {
            property bool groupRow: true
            property int pos: 0
            width: parent.width
            height: pairCol.implicitHeight + 44
            Rectangle {
                anchors.fill: parent
                color: Theme.surface
                topLeftRadius: parent.pos <= 1 ? 22 : 5; topRightRadius: topLeftRadius
                bottomLeftRadius: parent.pos === 0 || parent.pos === 3 ? 22 : 5; bottomRightRadius: bottomLeftRadius
            }
            Column {
                id: pairCol
                x: 22
                y: 22
                width: parent.width - 44
                spacing: 14
                Text {
                    text: "3.  Enter the code it shows"
                    color: Theme.text
                    font.family: Theme.sans
                    font.pixelSize: 15
                    font.weight: Font.Medium
                }
                CodeField { id: code }
                Row {
                    spacing: 10
                    Field {
                        id: addr
                        width: 230
                        placeholder: "IP address and port (optional)"
                    }
                    Btn {
                        kind: "filled"
                        icon: "link"
                        text: "Pair"
                        active: code.code.length === 6
                        busy: backend.busy === "phone"
                        onClicked: backend.pairPhone(code.code, addr.text)
                    }
                }
                Text {
                    width: parent.width
                    text: "The address is only needed if your network hides the phone; it's shown right under the code."
                    color: Theme.faint
                    font.family: Theme.sans
                    font.pixelSize: 12
                    wrapMode: Text.Wrap
                }
            }
        }
    }

    // ---- settings -----------------------------------------------------------------
    Group {
        title: "On the phone"
        ListRow {
            icon: "ads_click"
            title: "Show Claude on the phone"
            detail: "An orange glow at the edge and Claude's cursor at each tap, with a Stop button in the notification."
            Switch { checked: page.v("phone_overlay") !== false; onToggled: x => backend.set("phone_overlay", x) }
        }
        ListRow {
            icon: "lock"
            title: "Locked screens and sensitive apps"
            detail: "Claude never enters your PIN. Banking, payment, password and Settings apps ask you before it taps."
        }
    }

    Connections {
        target: backend
        function onTaskFinished(task, ok, msg) {
            if (task === "phone-pair" && ok) code.clear()
        }
    }
    Timer { interval: 20000; repeat: true; running: page.visible; onTriggered: backend.refreshPhone() }
    onVisibleChanged: if (visible) backend.refreshPhone()
}
