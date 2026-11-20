import QtQuick
import "."

// A glass panel. Content goes inside with the given padding. Cards arrive with
// a short rise and come into focus when their page appears (delay staggers them).
Item {
    id: card
    default property alias content: inner.data
    property real radius: 28
    property real padding: 26
    property int delay: 0
    property bool shown: true

    implicitWidth: inner.childrenRect.width + 2 * padding
    implicitHeight: inner.childrenRect.height + 2 * padding

    property real appear: 0
    opacity: Math.min(1, appear * 1.4)
    transform: Translate { y: (1 - card.appear) * 18 }
    Timer {
        id: kick
        interval: card.delay
        onTriggered: card.appear = 1
    }
    onShownChanged: { if (shown) { appear = 0; kick.restart() } else appear = 0 }
    Component.onCompleted: if (shown) kick.start()
    Behavior on appear { SpringAnimation { spring: 3.2; damping: 0.42; epsilon: 0.003 } }

    GlassSurface {
        target: card
        radius: card.radius
        band: 12 * Math.max(0, Math.min(1, card.appear))
    }
    Item {
        id: inner
        anchors.fill: parent
        anchors.margins: card.padding
    }
}
