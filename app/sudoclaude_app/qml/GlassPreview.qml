import QtQuick
import "."

// A live sample of the overlay pill with the current glass settings, over a busy
// little scene so the frost and the lens have something to work on.
Item {
    id: pv
    property string look: "auto"     // auto, light, dark
    property real frost: Theme.frost
    property real lens: Theme.lens
    property real tintMix: Theme.tintMix
    height: 220

    Item {
        id: scenery
        anchors.fill: parent
        layer.enabled: true
        Rectangle {
            anchors.fill: parent
            radius: 28
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: "#F3EDE3" }
                GradientStop { position: 0.48; color: "#F3EDE3" }
                GradientStop { position: 0.52; color: "#23211D" }
                GradientStop { position: 1.0; color: "#23211D" }
            }
        }
        // a few things for the glass to bend
        Repeater {
            model: 9
            Rectangle {
                required property int index
                x: 40 + index * (pv.width - 80) / 8 - 14
                y: 40 + (index % 3) * 52
                width: 28 + (index % 4) * 10
                height: width
                radius: index % 2 ? width / 2 : 8
                color: ["#D97757", "#4F7DD9", "#7FB069", "#E8B04B", "#9D6BD9", "#D95F8C", "#3FA7A0", "#C9643F", "#5C8DF2"][index]
            }
        }
        Repeater {
            model: 4
            Rectangle {
                required property int index
                x: 34
                y: 150 + index * 12
                width: pv.width - 68 - index * 60
                height: 5
                radius: 2.5
                color: index % 2 ? "#8A847A" : "#5A554D"
                opacity: 0.6
            }
        }
    }
    ShaderEffectSource {
        id: tex
        sourceItem: scenery
        hideSource: false
        live: true
        width: 0; height: 0
    }

    Item {
        id: pill
        width: 300; height: 54
        x: pv.width * 0.27 - width / 2
        anchors.verticalCenter: parent.verticalCenter
        readonly property real mode: pv.look === "light" ? 1 : pv.look === "dark" ? 0 : (x + width / 2 < pv.width / 2 ? 1 : 0)
        Glass {
            source: tex
            sourceSpace: scenery
            radius: 27
            band: 10 * pv.lens
            frost: pv.frost
            lens: pv.lens
            tintMix: pv.tintMix
            mode: pill.mode
            surround: pill.mode > 0.5 ? 0.92 : 0.12
            tintColor: "#2A2622"
            lightColor: "#FFFBF6"
        }
        Row {
            anchors.centerIn: parent
            spacing: 10
            Rectangle { width: 12; height: 12; radius: 6; color: "#D97757"; anchors.verticalCenter: parent.verticalCenter }
            Text { text: "Listening"; color: pill.mode > 0.5 ? "#1C1B19" : "#F6F2EC"
                   font.family: Theme.sans; font.pixelSize: 15; font.weight: Font.DemiBold }
            Text { text: "open spotify"; color: pill.mode > 0.5 ? "#4A463F" : "#CFC8BD"
                   font.family: Theme.sans; font.pixelSize: 15 }
        }
        // Drag it across the light and dark halves to see it adapt.
        MouseArea {
            anchors.fill: parent
            drag.target: pill
            drag.axis: Drag.XAxis
            drag.minimumX: 10
            drag.maximumX: pv.width - pill.width - 10
            cursorShape: Qt.OpenHandCursor
        }
    }
    Text {
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 12
        anchors.horizontalCenter: parent.horizontalCenter
        text: "Drag the pill across"
        color: "#9A938A"
        font.family: Theme.sans
        font.pixelSize: 12
    }
}
