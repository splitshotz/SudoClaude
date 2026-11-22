import QtQuick
import "."

// The floating glass sidebar. The indicator slides between items on a spring and
// the chosen icon fills in.
Item {
    id: bar
    property var items: []          // [{id, label, icon, badge?}]
    property string current: ""
    signal picked(string id)

    Glass { radius: 26; band: 12 }

    Row {
        x: 20
        y: 22
        spacing: 11
        Rectangle {
            width: 30; height: 30
            radius: 10
            color: Theme.accentFill
            Icon { anchors.centerIn: parent; name: "arrow_selector_tool"; size: 19; fill: 1; color: Theme.inkOnAccent }
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "SudoClaude"
            color: Theme.text
            font.family: Theme.serif
            font.pixelSize: 21
            font.variableAxes: ({ "opsz": 24, "wght": 500 })
        }
    }

    Item {
        id: list
        x: 10
        y: 76
        width: parent.width - 20
        height: items.length * 44

        Rectangle {
            id: indicator
            readonly property int idx: Math.max(0, bar.items.findIndex(i => i.id === bar.current))
            width: parent.width
            height: 40
            radius: 20
            y: idx * 44
            color: Theme.accentSoft
            Behavior on y { SpringAnimation { spring: Theme.springFast; damping: Theme.springDamp; epsilon: 0.2 } }
        }

        Repeater {
            model: bar.items
            Item {
                id: it
                required property var modelData
                required property int index
                readonly property bool on: bar.current === modelData.id
                y: index * 44
                width: list.width
                height: 40
                Rectangle {
                    anchors.fill: parent
                    radius: 20
                    color: Theme.text
                    opacity: !it.on && ma.containsMouse ? 0.05 : 0
                    Behavior on opacity { NumberAnimation { duration: 120 } }
                }
                Icon {
                    x: 14
                    anchors.verticalCenter: parent.verticalCenter
                    name: it.modelData.icon
                    size: 22
                    fill: it.on ? 1 : 0
                    color: it.on ? Theme.accentInk : Theme.text
                }
                Text {
                    x: 48
                    anchors.verticalCenter: parent.verticalCenter
                    text: it.modelData.label
                    color: it.on ? Theme.accentInk : Theme.text
                    font.family: Theme.sans
                    font.pixelSize: 15
                    font.weight: it.on ? Font.DemiBold : Font.Medium
                }
                Rectangle {
                    visible: !!it.modelData.badge
                    anchors.right: parent.right
                    anchors.rightMargin: 14
                    anchors.verticalCenter: parent.verticalCenter
                    width: 8; height: 8; radius: 4
                    color: Theme.accentFill
                }
                MouseArea {
                    id: ma
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: bar.picked(it.modelData.id)
                }
            }
        }
    }

    Column {
        x: 22
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 20
        width: parent.width - 44
        spacing: 4
        readonly property var st: backend.status || ({})
        Row {
            spacing: 8
            Rectangle {
                width: 8; height: 8; radius: 4
                anchors.verticalCenter: parent.verticalCenter
                color: parent.parent.st.installed ? Theme.good : Theme.warn
            }
            Text {
                text: parent.parent.st.installed
                      ? (parent.parent.st.claude_code && parent.parent.st.claude_desktop ? "Claude Code and the app"
                         : parent.parent.st.claude_code ? "Claude Code" : "Claude app")
                      : "Not set up"
                color: Theme.dim
                font.family: Theme.sans
                font.pixelSize: 12
                font.weight: Font.Medium
            }
        }
        Text {
            text: "Version " + (backend.version || backend.appVersion)
            color: Theme.faint
            font.family: Theme.sans
            font.pixelSize: 12
            leftPadding: 16
        }
    }
}
