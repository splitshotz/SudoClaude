import QtQuick
import "."

// Dashboard tile: what it is, how it's doing, and one thing you can do about it.
GlassCard {
    id: st
    property string label: ""
    property string headline: ""
    property string detail: ""
    property string tone: "good"      // good | warn | bad | off
    property string action: ""
    signal act()
    height: 240
    padding: 26

    Column {
        width: st.width - 2 * st.padding
        spacing: 10
        Row {
            spacing: 9
            Rectangle {
                width: 9; height: 9; radius: 4.5
                anchors.verticalCenter: parent.verticalCenter
                color: st.tone === "good" ? Theme.good : st.tone === "warn" ? Theme.warn
                     : st.tone === "bad" ? Theme.bad : Theme.dim
                SequentialAnimation on opacity {
                    running: st.tone === "good"
                    loops: Animation.Infinite
                    NumberAnimation { to: 0.45; duration: 1400; easing.type: Easing.InOutSine }
                    NumberAnimation { to: 1; duration: 1400; easing.type: Easing.InOutSine }
                }
            }
            Text {
                text: st.label.toUpperCase()
                color: Theme.dim
                font.family: Theme.sans
                font.pixelSize: 12
                font.weight: Font.DemiBold
                font.letterSpacing: 1.4
            }
        }
        Text {
            text: st.headline
            color: Theme.text
            font.family: Theme.serif
            font.pixelSize: 34
            width: parent.width
            elide: Text.ElideRight
        }
        Text {
            text: st.detail
            color: Theme.dim
            font.family: Theme.sans
            font.pixelSize: 14
            width: parent.width
            wrapMode: Text.Wrap
            maximumLineCount: 3
            lineHeight: 1.15
        }
    }
    GlassButton {
        visible: st.action.length
        text: st.action
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        onClicked: st.act()
    }
}
