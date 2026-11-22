import QtQuick
import "."

// A small status label.
Rectangle {
    id: c
    property string text: ""
    property string icon: ""
    property string tone: "neutral"   // neutral, good, warn, bad, accent
    readonly property color ink: tone === "good" ? Theme.good : tone === "warn" ? Theme.warn
                               : tone === "bad" ? Theme.bad : tone === "accent" ? Theme.accentInk : Theme.dim
    color: tone === "good" ? Theme.goodSoft : tone === "warn" ? Theme.warnSoft
         : tone === "bad" ? Theme.badSoft : tone === "accent" ? Theme.accentSoft : Theme.surfaceHi
    height: 28
    width: row.implicitWidth + 22
    radius: 8
    Row {
        id: row
        anchors.centerIn: parent
        spacing: 6
        Icon { visible: c.icon !== ""; name: c.icon; size: 16; color: c.ink; anchors.verticalCenter: parent.verticalCenter }
        Text {
            text: c.text
            color: c.ink
            font.family: Theme.sans
            font.pixelSize: 13
            font.weight: Font.Medium
            anchors.verticalCenter: parent.verticalCenter
        }
    }
}
