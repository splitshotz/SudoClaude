import QtQuick
import "."

Page {
    id: page
    signal doctor()
    function v(path) { Theme.cfgRev; return backend.get(path) }
    title: "Computer"
    subtitle: "How Claude uses your desktop. New Claude sessions pick these up."

    Group {
        title: "Asking first"
        ListRow {
            icon: "back_hand"
            title: "Ask before using apps"
            detail: page.v("approvals") === "strict" ? "Asks before every app."
                  : page.v("approvals") === "off" ? "Never asks."
                  : "Asks only for sensitive apps, like password managers and banking."
            Segmented {
                options: [{value: "smart", label: "Smart"}, {value: "strict", label: "Strict"}, {value: "off", label: "Off"}]
                value: page.v("approvals")
                onPicked: x => backend.set("approvals", x)
            }
        }
        ListRow {
            icon: "visibility_off"
            title: "Hide apps it hasn't been allowed to use"
            detail: "Their windows are blanked out before Claude sees a screenshot."
            Switch { checked: page.v("mask_unapproved"); onToggled: x => backend.set("mask_unapproved", x) }
        }
        ListRow {
            icon: "schedule"
            title: "Remember a yes for"
            Slider { width: 280; from: 10; to: 240; step: 10; decimals: 0; suffix: " min"
                     value: page.v("session_minutes"); onMoved: x => backend.set("session_minutes", Math.round(x)) }
        }
    }

    Group {
        title: "While Claude works"
        ListRow {
            icon: "touch_app"
            title: "Work next to me"
            detail: "Opens things beside you and only borrows the mouse while your hand is still."
            Switch { checked: page.v("copilot"); onToggled: x => backend.set("copilot", x) }
        }
        ListRow {
            icon: "stop_circle"
            title: "Escape stops Claude"
            Switch { checked: page.v("esc_to_stop"); onToggled: x => backend.set("esc_to_stop", x) }
        }
        ListRow {
            icon: "timer"
            title: "Hand control back after"
            detail: "Seconds without an action before Claude lets go."
            Slider { width: 280; from: 10; to: 120; step: 5; decimals: 0; suffix: " s"
                     value: page.v("idle_seconds"); onMoved: x => backend.set("idle_seconds", Math.round(x)) }
        }
        ListRow {
            icon: "notifications"
            title: "Notifications"
            detail: "Start and stop popups when the overlay isn't showing."
            Switch { checked: page.v("notifications") !== false; onToggled: x => backend.set("notifications", x) }
        }
        ListRow {
            icon: "sports_esports"
            title: "Stay out of the way in games"
            detail: "Nothing pops up over a game, and the voice won't load while one runs."
            Switch { checked: page.v("hide_in_games") !== false; onToggled: x => backend.set("hide_in_games", x) }
        }
    }

    Group {
        ListRow {
            icon: "health_and_safety"
            title: "Health check"
            detail: "Runs SudoClaude's self-test: screenshots, input, accessibility and the overlay."
            Btn { kind: "tonal"; text: "Run"; small: true; onClicked: page.doctor() }
        }
    }

    SectionReset { section: "computer" }
}
