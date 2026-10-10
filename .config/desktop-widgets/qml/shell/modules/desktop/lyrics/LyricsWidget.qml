pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import shell.services
import "../Singletons"
import Eclipse.Ui.Singletons

// The wallpaper's lyrics panel: only the words of what is playing, nothing
// else. Ported from impasto's LyricsFace
// (github.com/andreumassanet/impasto) onto this config's services: Lyrics
// carries the lrclib lookup and the current line, Media/Music the player and
// the shared playback clock.
//
// Three looks (Config.musicStyle is the music widget's; this one has its own
// lyricsDesign): `line` shows the sung line large with the next one under it;
// `band` is a short wide strip for along an edge; `sheet` is the tall 4x4
// look with the lines scrolling past, the sung one held mid-panel. With no
// line to show, the reason is shown where the line would be.
Item {
    id: root

    property string design: "line"   // line | band | sheet
    property real s: 1
    property bool active: true
    property real underL: Scheme.wallLstar
    // WidgetSlot pins a hex here to paint this widget's ink; "" follows the wallpaper.
    property string inkColorA: ""

    readonly property bool band: root.design === "band"
    readonly property bool sheet: root.design === "sheet"

    implicitWidth: root.sheet ? 360 * root.s : (root.band ? 460 * root.s : 320 * root.s)
    implicitHeight: root.sheet ? 360 * root.s : (root.band ? 72 * root.s : 150 * root.s)

    // The lookup and the line tracker run only while a surface wants them.
    // Music is held too: its shared playback clock (elapsed) only advances
    // while someone holds it, and with the music widget off this panel is the
    // only holder -- without this the sung line would never move along.
    readonly property bool wanted: root.active && root.visible
    onWantedChanged: {
        Lyrics.hold(root, root.wanted);
        Music.hold(root, root.wanted);
    }
    Component.onCompleted: {
        Lyrics.hold(root, root.wanted);
        Music.hold(root, root.wanted);
    }
    Component.onDestruction: {
        Lyrics.hold(root, false);
        Music.hold(root, false);
    }

    readonly property bool singing: Lyrics.available && Lyrics.synced && Lyrics.index >= 0
    readonly property color ink: Theme.inkOn2(root.underL, root.inkColorA)
    readonly property color dim: Theme.inkDimOn2(root.underL, root.inkColorA)
    readonly property int pad: 18 * root.s

    function statusText() {
        switch (Lyrics.status) {
        case "off": return I18n.tr("Lyrics are off");
        case "idle": return I18n.tr("Nothing playing");
        case "loading": return I18n.tr("Looking for lyrics");
        case "instrumental": return I18n.tr("Instrumental");
        case "plain": return I18n.tr("Lyrics, untimed");
        default: return I18n.tr("No lyrics for this one");
        }
    }

    // ── line / band: the sung line, the next one where there is room ──────
    // line: the sung line large, the next one under it. band: a one-line
    // strip for along a screen edge, sized so its text dominates the width.
    Column {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.margins: root.pad
        visible: !root.sheet
        spacing: 4 * root.s

        // band's eyebrow: the track name, so the strip reads as a caption
        Text {
            width: parent.width
            visible: root.band && Music.title !== ""
            text: Music.title
            elide: Text.ElideRight
            font.family: Theme.font
            font.pixelSize: 10 * root.s
            font.weight: Font.Medium
            font.letterSpacing: 1.5
            font.capitalization: Font.AllUppercase
            color: root.dim
        }

        Text {
            id: sung
            width: parent.width
            text: root.singing
                ? (Lyrics.currentText !== "" ? Lyrics.currentText : "♪")
                : (Lyrics.available && Lyrics.synced) ? "♪"
                : root.statusText()
            wrapMode: root.band ? Text.NoWrap : Text.Wrap
            maximumLineCount: root.band ? 1 : 3
            elide: Text.ElideRight
            font.family: Theme.font
            font.pixelSize: (root.band ? 22 : 26) * root.s
            font.weight: Font.Bold
            color: root.singing ? root.ink : root.dim

            onTextChanged: turn.restart()

            NumberAnimation {
                id: turn
                target: sung
                property: "opacity"
                from: 0
                to: 1
                duration: Theme.medium
                easing.type: Theme.ease
            }
        }

        Text {
            width: parent.width
            visible: !root.band
            text: root.singing ? Lyrics.nextText : ""
            elide: Text.ElideRight
            font.family: Theme.font
            font.pixelSize: 15 * root.s
            font.weight: Font.DemiBold
            color: root.dim
        }
    }

    // ── sheet: the lines running past, the sung one held mid-panel ────────
    Text {
        anchors.centerIn: lines
        width: lines.width
        visible: root.sheet && (!Lyrics.available || Lyrics.instrumental)
        text: root.statusText()
        wrapMode: Text.Wrap
        horizontalAlignment: Text.AlignHCenter
        font.family: Theme.font
        font.pixelSize: 20 * root.s
        font.weight: Font.Bold
        color: root.dim
    }

    ListView {
        id: lines
        anchors.fill: parent
        anchors.leftMargin: root.pad
        anchors.rightMargin: root.pad
        anchors.topMargin: 8 * root.s
        anchors.bottomMargin: 8 * root.s
        visible: root.sheet && Lyrics.available && !Lyrics.instrumental
        model: root.sheet && Lyrics.available ? Lyrics.lines : []
        spacing: 10 * root.s
        interactive: false
        currentIndex: Lyrics.synced ? Lyrics.index : -1
        highlightRangeMode: Lyrics.synced ? ListView.StrictlyEnforceRange : ListView.NoHighlightRange
        preferredHighlightBegin: height / 2 - 16
        preferredHighlightEnd: height / 2 + 16
        highlightMoveDuration: Theme.slow
        header: Item { width: 1; height: Lyrics.synced ? lines.height / 2 : root.pad }
        footer: Item { width: 1; height: lines.height / 2 }

        layer.enabled: true
        layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: fade
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1
        }

        delegate: Text {
            id: verse
            required property var modelData
            required property int index

            readonly property int away: Lyrics.index < 0
                ? (Lyrics.synced ? verse.index + 1 : 1)
                : Math.abs(verse.index - Lyrics.index)

            width: lines.width
            text: verse.modelData.text !== "" ? verse.modelData.text : "♪"
            wrapMode: Text.Wrap
            font.family: Theme.font
            font.pixelSize: 20 * root.s
            font.weight: Font.Bold
            color: root.ink
            opacity: verse.away === 0 ? 1 : Math.max(0.2, 0.45 - 0.1 * (verse.away - 1))

            Behavior on opacity {
                NumberAnimation { duration: Theme.slow; easing.type: Theme.ease }
            }
        }
    }

    Rectangle {
        id: fade
        anchors.fill: lines
        visible: false
        layer.enabled: true
        gradient: Gradient {
            GradientStop { position: 0.0; color: "transparent" }
            GradientStop { position: 0.2; color: "white" }
            GradientStop { position: 0.8; color: "white" }
            GradientStop { position: 1.0; color: "transparent" }
        }
    }
}
