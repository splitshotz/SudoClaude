import QtQuick
import "."

// A small floating glass capsule that holds the page's actions, no wider than
// the buttons in it.
Item {
    id: tb
    default property alias actions: acts.data
    height: 50
    width: acts.implicitWidth + 16
    Behavior on width { SpringAnimation { spring: 3.2; damping: 0.46; epsilon: 0.3 } }

    Glass { radius: 25; band: 10 }

    Row {
        id: acts
        anchors.centerIn: parent
        spacing: 2
    }
}
