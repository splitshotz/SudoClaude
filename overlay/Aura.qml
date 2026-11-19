import QtQuick
import QtQuick.Shapes

Item {
    id: a
    property real intensity: 0
    property color color: "#D97757"
    visible: intensity > 0.003
    opacity: Math.min(1, intensity)

    Shape {
        id: disc
        width: a.width; height: a.width
        y: (a.height - a.width) / 2
        transform: Scale { origin.x: disc.width / 2; origin.y: disc.height / 2; yScale: a.height / Math.max(1, a.width) }
        ShapePath {
            strokeColor: "transparent"
            fillGradient: RadialGradient {
                centerX: disc.width / 2; centerY: disc.height / 2
                focalX: centerX; focalY: centerY
                centerRadius: disc.width / 2
                GradientStop { position: 0.0; color: Qt.rgba(a.color.r, a.color.g, a.color.b, 0.7) }
                GradientStop { position: 0.4; color: Qt.rgba(a.color.r, a.color.g, a.color.b, 0.3) }
                GradientStop { position: 0.75; color: Qt.rgba(a.color.r, a.color.g, a.color.b, 0.05) }
                GradientStop { position: 1.0; color: Qt.rgba(a.color.r, a.color.g, a.color.b, 0.0) }
            }
            PathAngleArc {
                centerX: disc.width / 2; centerY: disc.height / 2
                radiusX: disc.width / 2; radiusY: disc.width / 2
                startAngle: 0; sweepAngle: 360
            }
        }
    }
}
