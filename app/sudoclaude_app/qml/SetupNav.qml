import QtQuick
import "."

// Setup's step dots and buttons, on glass. It lives in the floating layer so the
// glass refracts the setup page instead of itself.
Item {
    id: nav
    property Item setup
    width: setup.colWidth + 24
    height: 64
    x: setup.colLeft - 12
    visible: setup.step !== 4
    Glass { radius: 32; band: 11 }
    Row {
        anchors.left: parent.left
        anchors.leftMargin: 22
        anchors.verticalCenter: parent.verticalCenter
        spacing: 6
        Repeater {
            model: 6
            Rectangle {
                required property int index
                width: index === setup.step ? 22 : 7
                height: 7
                radius: 3.5
                color: index <= setup.step ? Theme.accentFill : Theme.rgba(Theme.text, 0.2)
                anchors.verticalCenter: parent.verticalCenter
                Behavior on width { SpringAnimation { spring: 4; damping: 0.45 } }
            }
        }
    }
    Row {
        anchors.right: parent.right
        anchors.rightMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        spacing: 6
        Btn {
            kind: "text"
            text: setup.step === 5 && setup.failed ? "Back" : "Back"
            visible: setup.step > 0 && setup.step !== 5 || setup.failed
            onClicked: setup.failed ? setup.step = 2 : setup.back()
        }
        Btn {
            icon: setup.step === 5 ? "" : "arrow_forward"
            text: setup.step === 0 ? "Get started" : setup.step === 3 ? "Install"
                : setup.step === 5 ? (setup.failed ? "Try again" : "Open SudoClaude") : "Continue"
            active: setup.step !== 1 || setup.ready
            onClicked: {
                if (setup.step === 5) {
                    if (setup.failed) { setup.step = 4; setup.startInstall() }
                    else { setup.dismissed = true; backend.refresh() }
                } else setup.next()
            }
        }
    }
}
