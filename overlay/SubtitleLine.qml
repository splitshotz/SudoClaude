import QtQuick

// One line of transcript that grows a word at a time. New words fade and come
// into focus where they land (two faint offset copies converge on the word, so
// no layer effects are needed). When the line outgrows maxWidth it scrolls with
// a spring and the oldest words fade out at the left edge. Revisions from live
// speech recognition only touch the words that actually changed.
Item {
    id: line

    property string text: ""
    property color color: "white"
    property string family: "Google Sans Flex"
    property int pixelSize: 14
    property int weight: Font.Normal
    property bool italic: false
    property real nudge: 0
    property real maxWidth: 520
    readonly property real contentWidth: row.implicitWidth

    implicitHeight: fm.height
    height: implicitHeight
    clip: true

    FontMetrics {
        id: fm
        font.family: line.family
        font.pixelSize: line.pixelSize
        font.weight: line.weight
        font.italic: line.italic
    }

    ListModel { id: words }

    function sync() {
        const next = line.text.split(/\s+/).filter(w => w.length)
        let k = 0
        while (k < words.count && k < next.length && words.get(k).w === next[k]) k++
        if (words.count > k) words.remove(k, words.count - k)
        for (let i = k; i < next.length; i++) words.append({ w: next[i] })
    }
    onTextChanged: sync()
    Component.onCompleted: sync()

    // Only scroll once the text is longer than the line can ever get; while the
    // pill is still widening, new words are simply revealed as it opens.
    readonly property bool overflowing: row.implicitWidth > maxWidth + 0.5

    Row {
        id: row
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: line.nudge
        spacing: fm.advanceWidth(" ")
        // Keep the newest words in view; glide rather than jump.
        x: line.overflowing ? line.maxWidth - implicitWidth : 0
        Behavior on x { SpringAnimation { spring: 3.2; damping: 0.62; epsilon: 0.2 } }

        Repeater {
            model: words
            Item {
                id: word
                required property string w
                width: main.implicitWidth
                height: main.implicitHeight
                // 0 when it's just arrived, 1 once it has settled in.
                property real settle: 0
                Component.onCompleted: arrive.start()
                NumberAnimation on settle {
                    id: arrive
                    running: false
                    from: 0; to: 1
                    duration: 340
                    easing.type: Easing.OutCubic
                }
                // Words scrolling out to the left fade away.
                readonly property real edge: line.overflowing
                    ? Math.max(0, Math.min(1, (word.x + row.x) / 36 + 0.1)) : 1

                Text {
                    id: main
                    text: word.w
                    color: line.color
                    font: fm.font
                    opacity: word.settle * word.edge
                    transform: Translate { y: (1 - word.settle) * 2.5 }
                }
                // Soft focus: two faint copies just off the word that slide in
                // and vanish as it settles.
                Text {
                    text: word.w
                    color: line.color
                    font: fm.font
                    x: -(1 - word.settle) * 3
                    opacity: (1 - word.settle) * 0.35 * word.edge
                    visible: word.settle < 0.99
                }
                Text {
                    text: word.w
                    color: line.color
                    font: fm.font
                    x: (1 - word.settle) * 3
                    opacity: (1 - word.settle) * 0.35 * word.edge
                    visible: word.settle < 0.99
                }
            }
        }
    }
}
