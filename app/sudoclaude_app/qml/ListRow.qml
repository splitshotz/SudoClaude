import QtQuick
import "."

// One row of a Group: optional icon, title and detail, and a control on the right.
Item {
    id: r
    property bool groupRow: true
    property int pos: 0            // 0 alone, 1 first, 2 middle, 3 last (set by Group)
    property string icon: ""
    property string title: ""
    property string detail: ""
    property color iconTone: Theme.surfaceHi
    property color iconInk: Theme.text
    property bool clickable: false
    property bool chevron: false
    property real trailingWidth: trail.childrenRect.width
    property bool active: true
    default property alias content: trail.data
    signal clicked()

    width: parent ? parent.width : 600
    height: Math.max(icon ? 72 : 64, texts.implicitHeight + 28,
                     trail.childrenRect.height + 28)
    opacity: active ? 1 : 0.45
    Behavior on opacity { NumberAnimation { duration: 160 } }

    readonly property real outer: 22
    readonly property real inner: 5
    Rectangle {
        anchors.fill: parent
        color: Theme.surface
        topLeftRadius: r.pos <= 1 ? r.outer : r.inner
        topRightRadius: r.pos <= 1 ? r.outer : r.inner
        bottomLeftRadius: r.pos === 0 || r.pos === 3 ? r.outer : r.inner
        bottomRightRadius: r.pos === 0 || r.pos === 3 ? r.outer : r.inner
        Rectangle {
            anchors.fill: parent
            topLeftRadius: parent.topLeftRadius; topRightRadius: parent.topRightRadius
            bottomLeftRadius: parent.bottomLeftRadius; bottomRightRadius: parent.bottomRightRadius
            color: Theme.text
            opacity: r.clickable ? (ma.pressed ? 0.08 : ma.containsMouse ? 0.04 : 0) : 0
            Behavior on opacity { NumberAnimation { duration: 120 } }
        }
    }
    Rectangle {
        id: badge
        visible: r.icon !== ""
        x: 18
        anchors.verticalCenter: parent.verticalCenter
        width: 40; height: 40
        radius: 13
        color: r.iconTone
        Icon { anchors.centerIn: parent; name: r.icon; size: 22; color: r.iconInk }
    }
    Column {
        id: texts
        anchors.verticalCenter: parent.verticalCenter
        x: r.icon ? 74 : 22
        width: parent.width - x - (r.trailingWidth > 0 ? r.trailingWidth + 40 : 22) - (r.chevron ? 30 : 0)
        spacing: 3
        Text {
            width: parent.width
            text: r.title
            color: Theme.text
            font.family: Theme.sans
            font.pixelSize: 15
            font.weight: Font.Medium
            wrapMode: Text.Wrap
        }
        Text {
            width: parent.width
            visible: r.detail !== ""
            text: r.detail
            color: Theme.dim
            font.family: Theme.sans
            font.pixelSize: 13
            wrapMode: Text.Wrap
            lineHeight: 1.12
        }
    }
    Item {
        id: trail
        anchors.right: parent.right
        anchors.rightMargin: r.chevron ? 46 : 20
        anchors.verticalCenter: parent.verticalCenter
        width: childrenRect.width
        height: childrenRect.height
    }
    Icon {
        visible: r.chevron
        anchors.right: parent.right
        anchors.rightMargin: 16
        anchors.verticalCenter: parent.verticalCenter
        name: "chevron_right"
        color: Theme.faint
    }
    MouseArea {
        id: ma
        anchors.fill: parent
        z: -1
        enabled: r.clickable
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: r.clicked()
    }
}
