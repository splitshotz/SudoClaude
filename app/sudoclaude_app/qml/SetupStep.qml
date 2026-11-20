import QtQuick
import QtQuick.Effects
import "."

// One setup step. The leaving step drifts up and goes out of focus; the next
// one rises into place and sharpens.
Item {
    id: s
    property int index
    property int current
    readonly property bool on: current === index
    property real t: on ? 1 : 0
    Behavior on t { NumberAnimation { duration: 700; easing.type: Easing.OutCubic } }
    anchors.fill: parent
    visible: t > 0.003
    opacity: t
    transform: Translate { y: (1 - s.t) * (s.on ? 28 : -28) }
    layer.enabled: visible
    layer.effect: MultiEffect { blurEnabled: true; blurMax: 40; blur: 1 - s.t }
}
