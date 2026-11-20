import QtQuick
import "."

// Pill button in glass. `accent` makes it orange glass for the main action.
Item {
    id: btn
    property string text: ""
    property bool accent: false
    property bool danger: false
    // Cream (or ink) pill with an arrow, for the one thing to do next.
    property bool primary: false
    property bool arrow: primary
    property bool enabled_: true
    signal clicked()

    implicitWidth: label.implicitWidth + (arrow ? 70 : 44)
    implicitHeight: 44
    opacity: enabled_ ? 1 : 0.45
    scale: area.pressed ? 0.96 : area.containsMouse ? 1.02 : 1
    Behavior on scale { SpringAnimation { spring: 6; damping: 0.45; epsilon: 0.002 } }

    Rectangle {
        visible: btn.primary
        anchors.fill: parent
        radius: height / 2
        color: area.containsMouse ? Qt.lighter(Theme.pill, Theme.dark ? 1.04 : 1.25) : Theme.pill
        Behavior on color { ColorAnimation { duration: 160 } }
    }
    GlassSurface {
        visible: !btn.primary
        target: btn
        radius: btn.height / 2
        band: 9
        margin: 14
        tintColor: btn.accent ? Theme.accent : btn.danger ? Theme.bad
                 : (Theme.dark ? "#2A2522" : "#FFFBF6")
        lightColor: tintColor
        tintMix: btn.accent || btn.danger ? (area.containsMouse ? 0.72 : 0.62) : Theme.tintMix
        Behavior on tintMix { NumberAnimation { duration: 160 } }
    }
    Text {
        id: label
        anchors.centerIn: parent
        anchors.horizontalCenterOffset: btn.arrow ? -12 : 0
        text: btn.text
        color: btn.primary ? Theme.pillText : btn.accent || btn.danger ? "white" : Theme.text
        font.family: Theme.sans
        font.pixelSize: 15
        font.weight: Font.DemiBold
    }
    Text {
        visible: btn.arrow
        anchors.left: label.right
        anchors.leftMargin: 10
        anchors.verticalCenter: label.verticalCenter
        text: "\u2192"
        color: label.color
        font.family: Theme.sans
        font.pixelSize: 17
        transform: Translate { x: area.containsMouse ? 3 : 0; Behavior on x { SpringAnimation { spring: 5; damping: 0.4 } } }
    }
    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        enabled: btn.enabled_
        cursorShape: Qt.PointingHandCursor
        onClicked: btn.clicked()
    }
}
