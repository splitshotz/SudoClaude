import QtQuick
import "."

// "Reset" for one section, as a quiet text button at the end of a page.
Row {
    property string section: ""
    property string label: "Reset these to defaults"
    spacing: 8
    Btn {
        kind: "text"
        small: true
        icon: "restart_alt"
        text: parent.label
        onClicked: backend.resetSection(parent.section)
    }
}
