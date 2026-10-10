pragma ComponentBehavior: Bound
import QtQuick
import Eclipse.Ui.Singletons

/**
 * A plain-QML preview of the lyrics desktop widget for the Desktop Widgets
 * section, mirroring the live lyrics/LyricsWidget.qml in its three designs --
 * `line` (the sung line large with the next under it), `band` (a slim strip)
 * and `sheet` (the lines scrolling past, the sung one mid-panel) -- with fixed
 * sample lines and no Lyrics singleton. Ink follows the hub theme through
 * Tokens; the background is transparent so the card surface shows through.
 */
Item {
    id: root

    property string design: "line"   // line | band | sheet
    readonly property bool band: root.design === "band"
    readonly property bool sheet: root.design === "sheet"

    readonly property var lines: [
        "I heard that you're settled down",
        "That you found a girl and you're married now",
        "I heard that your dreams came true",
        "Guess she gave you things I didn't give to you"
    ]

    implicitWidth: root.sheet ? 360 : (root.band ? 420 : 300)
    implicitHeight: root.sheet ? 360 : (root.band ? 84 : 130)

    Column {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.margins: 18
        visible: !root.sheet
        spacing: 6

        Text {
            width: parent.width
            text: I18n.tr("I heard that you're settled down")
            wrapMode: Text.Wrap
            maximumLineCount: root.band ? 2 : 3
            elide: Text.ElideRight
            font.family: Tokens.ui
            font.pixelSize: root.band ? 30 : 24
            font.weight: Font.Bold
            color: Tokens.sun
        }

        Text {
            width: parent.width
            visible: !root.band
            text: I18n.tr("That you found a girl and you're married now")
            elide: Text.ElideRight
            font.family: Tokens.ui
            font.pixelSize: 14
            font.weight: Font.DemiBold
            color: Tokens.inkMuted
        }
    }

    Text {
        anchors.centerIn: parent
        visible: root.sheet
        width: parent.width - 36
        text: root.lines.join("\n")
        wrapMode: Text.Wrap
        horizontalAlignment: Text.AlignHCenter
        font.family: Tokens.ui
        font.pixelSize: 18
        font.weight: Font.Bold
        color: Tokens.ink
        opacity: 0.8
    }
}
