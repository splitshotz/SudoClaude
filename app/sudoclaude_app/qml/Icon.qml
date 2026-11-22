import QtQuick
import "."

// Material Symbols Rounded, looked up by name. FILL animates between outlined and filled.
Text {
    id: icon
    property string name: ""
    property real size: 22
    property real fill: 0
    property real weight: 400
    Behavior on fill { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

    readonly property var codes: ({
        "add": 0xE145,
        "ads_click": 0xE762,
        "arrow_back": 0xE5C4,
        "arrow_forward": 0xE5C8,
        "arrow_selector_tool": 0xF82F,
        "auto_mode": 0xEC20,
        "back_hand": 0xE764,
        "battery_charging_full": 0xE1A3,
        "battery_full": 0xE1A4,
        "blur_on": 0xE3A5,
        "bolt": 0xEA0B,
        "brightness_auto": 0xE1AB,
        "cancel": 0xE5C9,
        "cast": 0xE307,
        "chat": 0xE0B7,
        "check": 0xE5CA,
        "check_circle": 0xE86C,
        "chevron_right": 0xE409,
        "close": 0xE14C,
        "code": 0xE86F,
        "contrast": 0xEB37,
        "dark_mode": 0xE51C,
        "delete": 0xE872,
        "desktop_windows": 0xE30C,
        "devices": 0xE1B1,
        "do_not_disturb_on": 0xE15C,
        "dock_to_right": 0xF7E4,
        "download": 0xE171,
        "edit": 0xE150,
        "error": 0xE000,
        "expand_more": 0xE5CF,
        "folder": 0xE2C7,
        "front_hand": 0xE769,
        "graphic_eq": 0xE1B8,
        "health_and_safety": 0xE1D5,
        "hearing": 0xE023,
        "help": 0xE887,
        "history": 0xE28E,
        "info": 0xE88E,
        "ink_highlighter": 0xE6D1,
        "keyboard": 0xE312,
        "keyboard_alt": 0xF028,
        "language": 0xE894,
        "layers": 0xE53B,
        "lens_blur": 0xF029,
        "light_mode": 0xE518,
        "link": 0xE157,
        "lock": 0xE88D,
        "lock_open": 0xE898,
        "memory": 0xE322,
        "mic": 0xE029,
        "mobile_off": 0xE201,
        "music_note": 0xE3A1,
        "notifications": 0xE7F4,
        "open_in_new": 0xE895,
        "palette": 0xE3B7,
        "person": 0xE7FD,
        "phone_android": 0xE324,
        "phonelink": 0xE1B1,
        "phonelink_off": 0xE327,
        "progress_activity": 0xE9D0,
        "psychology": 0xEA4A,
        "refresh": 0xE5D5,
        "restart_alt": 0xF053,
        "schedule": 0xE192,
        "screen_share": 0xE0E2,
        "settings": 0xE8B8,
        "smartphone": 0xE0D4,
        "space_dashboard": 0xE66B,
        "sports_esports": 0xE6EC,
        "stop_circle": 0xEF71,
        "sync": 0xE627,
        "system_update": 0xE62A,
        "task_alt": 0xE2E6,
        "timer": 0xE425,
        "toggle_on": 0xE9F6,
        "touch_app": 0xE913,
        "tune": 0xE429,
        "visibility": 0xE417,
        "visibility_off": 0xE8F5,
        "volume_down": 0xE04D,
        "wallpaper": 0xE1BC,
        "warning": 0xE002,
        "wifi": 0xE63E
    })
    text: codes[name] !== undefined ? String.fromCodePoint(codes[name]) : ""
    color: Theme.text
    font.family: Theme.icons
    font.pixelSize: size
    font.variableAxes: ({ "FILL": fill, "wght": weight })
    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter
    width: size
    height: size
}
