import QtQuick
import "."

Page {
    id: page
    signal askUninstall()
    title: "About"
    subtitle: "SudoClaude gives Claude your desktop and your phone, on your terms."

    Group {
        ListRow {
            icon: "folder"
            title: "Installed in"
            detail: backend.repoPath
        }
        ListRow {
            icon: "code"
            title: "Source code"
            detail: backend.repoUrl.replace("https://", "")
            clickable: true
            chevron: true
            onClicked: Qt.openUrlExternally(backend.repoUrl)
        }
        ListRow {
            icon: "info"
            title: "Versions"
            detail: "SudoClaude " + (backend.version || "?") + " · App " + backend.appVersion
        }
    }

    Group {
        ListRow {
            icon: "delete"
            iconTone: Theme.badSoft
            iconInk: Theme.bad
            title: "Uninstall SudoClaude"
            detail: "Removes Claude's access, the keybinds and the voice service. Your files stay."
            Btn { kind: "danger"; small: true; text: "Uninstall"; onClicked: page.askUninstall() }
        }
    }
}
