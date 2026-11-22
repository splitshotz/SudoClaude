import QtQuick
import "."

Page {
    id: page
    function v(path) { Theme.cfgRev; return backend.get(path) }
    title: "Appearance"
    subtitle: "How Claude shows up on your screen, and how this app looks."

    GlassPreview {
        width: parent.width
        look: page.v("glass.appearance") || "auto"
    }

    Group {
        title: "Overlay"
        ListRow {
            icon: "layers"
            title: "Show Claude on screen"
            detail: "The glass pill, Claude's cursor and the edge light while it works."
            Switch { checked: page.v("overlay") !== false; onToggled: x => backend.set("overlay", x) }
        }
        ListRow {
            icon: "ink_highlighter"
            title: "Edge while working"
            active: page.v("overlay") !== false
            Segmented {
                options: [{value: "hairline", label: "Line"}, {value: "glow", label: "Glow"},
                          {value: "brackets", label: "Corners"}, {value: "minimal", label: "None"}]
                value: page.v("overlay_style")
                onPicked: x => backend.set("overlay_style", x)
            }
        }
        ListRow {
            icon: "dock_to_right"
            title: "Where the pill rests"
            detail: "You can also drag or flick it there."
            Grid {
                id: pos
                columns: 3
                spacing: 4
                property string at: { Theme.cfgRev; return backend.pillPosition() }
                Repeater {
                    model: ["top-left", "top", "top-right", "left", "", "right", "bottom-left", "bottom", "bottom-right"]
                    Rectangle {
                        required property string modelData
                        readonly property bool on: pos.at === modelData
                        width: 30; height: 20
                        radius: on ? 10 : 6
                        color: !modelData ? "transparent" : on ? Theme.accentFill : Theme.surfaceHi
                        Behavior on radius { SpringAnimation { spring: 5; damping: 0.4 } }
                        Behavior on color { ColorAnimation { duration: 150 } }
                        MouseArea {
                            anchors.fill: parent
                            enabled: parent.modelData !== ""
                            cursorShape: Qt.PointingHandCursor
                            onClicked: backend.setPillPosition(parent.modelData)
                        }
                    }
                }
            }
        }
    }

    Group {
        title: "Glass"
        ListRow {
            icon: "contrast"
            title: "Light or dark"
            detail: "Automatic goes light over bright windows and dark over dark ones."
            Segmented {
                options: [{value: "auto", label: "Auto"}, {value: "light", label: "Light"}, {value: "dark", label: "Dark"}]
                value: page.v("glass.appearance")
                onPicked: x => backend.set("glass.appearance", x)
            }
        }
        ListRow {
            icon: "blur_on"
            title: "Frost"
            detail: "How much it blurs what's behind it."
            Slider { width: 280; from: 0; to: 12; step: 0.5; suffix: " px"
                     value: page.v("glass.frost"); onMoved: x => backend.set("glass.frost", x) }
        }
        ListRow {
            icon: "lens_blur"
            title: "Refraction"
            detail: "How strongly the edge bends what's under it."
            Slider { width: 280; from: 0; to: 2; step: 0.05; decimals: 2
                     value: page.v("glass.lens"); onMoved: x => backend.set("glass.lens", x) }
        }
        ListRow {
            icon: "palette"
            title: "Tint"
            detail: "How much of the glass's own color shows."
            Slider { width: 280; from: 0; to: 0.4; step: 0.01; decimals: 2
                     format: x => Math.round(x * 100) + "%"
                     value: page.v("glass.tint"); onMoved: x => backend.set("glass.tint", x) }
        }
    }

    Group {
        title: "This app"
        ListRow {
            icon: "dark_mode"
            title: "Theme"
            Segmented {
                options: [{value: "system", label: "System"}, {value: "light", label: "Light"}, {value: "dark", label: "Dark"}]
                value: backend.theme
                onPicked: x => backend.setTheme(x)
            }
        }
    }

    SectionReset { section: "appearance" }
}
