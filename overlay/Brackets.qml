import QtQuick
import QtQuick.Shapes
import QtQuick.Effects

Item {
    id: b
    property real intensity: 0
    property real rx: 0
    property real ry: 0
    property real rw: width
    property real rh: height
    property real len: 54
    property real tl: 1
    property real tr: 1
    property real bl: 1
    property real br: 1
    property color color: "#D97757"
    property color colorHi: "#EBA286"
    visible: intensity > 0.003

    component Corner: Shape {
        id: cn
        property real sx: 1
        property real sy: 1
        property real w: 1
        width: b.len; height: b.len
        opacity: w
        ShapePath {
            strokeColor: b.colorHi
            strokeWidth: 3
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            startX: cn.sx > 0 ? 1.5 : b.len - 1.5
            startY: cn.sy > 0 ? b.len : 0
            PathLine { x: cn.sx > 0 ? 1.5 : b.len - 1.5; y: cn.sy > 0 ? 14 : b.len - 14 }
            PathArc {
                x: cn.sx > 0 ? 14 : b.len - 14
                y: cn.sy > 0 ? 1.5 : b.len - 1.5
                radiusX: 12.5; radiusY: 12.5
                direction: (cn.sx * cn.sy > 0) ? PathArc.Clockwise : PathArc.Counterclockwise
            }
            PathLine { x: cn.sx > 0 ? b.len : 0; y: cn.sy > 0 ? 1.5 : b.len - 1.5 }
        }
    }

    Item {
        id: frame
        anchors.fill: parent
        opacity: Math.min(1, b.intensity)
        layer.enabled: true
        layer.samples: 4
        Corner { x: b.rx; y: b.ry; sx: 1; sy: 1; w: b.tl }
        Corner { x: b.rx + b.rw - b.len; y: b.ry; sx: -1; sy: 1; w: b.tr }
        Corner { x: b.rx; y: b.ry + b.rh - b.len; sx: 1; sy: -1; w: b.bl }
        Corner { x: b.rx + b.rw - b.len; y: b.ry + b.rh - b.len; sx: -1; sy: -1; w: b.br }
    }
    MultiEffect {
        anchors.fill: frame
        source: frame
        autoPaddingEnabled: false
        blurEnabled: true
        blur: 1.0
        blurMax: 24
        colorization: 1.0
        colorizationColor: b.color
        opacity: 0.8 * Math.min(1, b.intensity)
    }
}
