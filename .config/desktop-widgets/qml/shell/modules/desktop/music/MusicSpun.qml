pragma ComponentBehavior: Bound
import QtQuick
import shell.services
import ".."
import "../../../components"

// The "vinyl" music design: Spun's mini mode on the wallpaper. The record (with
// the album art as its label) under a fixed light, Spun's soft circular shadow
// and gold tonearm, spinning up to 33⅓ rpm and easing to a stop the way Spun's
// deck does; the arm walks the grooves with the track. Hovering brings up
// Spun's control pill (previous · play · next); at rest that slot carries the
// track's title so the desktop still says what is playing.
// Spun © yappologistic, PolyForm Noncommercial 1.0.0 — see ./NOTICE.
Item {
    id: root

    property real s: 1
    property string art: ""
    property color accent: "#c6a25a"
    property color ink: "white"
    property color dim: "#aaaaaa"
    property bool active: true
    property bool hovered: false
    // The Music widget's Visualiser option: the ring round the record.
    property string viz: "bars"            // bars | wave

    readonly property var player: Media.player
    readonly property bool playing: Media.playing
    readonly property real length: root.player && root.player.length > 0 ? root.player.length : 0

    // Spun's mini window: 300 wide, the 440 platter at .64 inset 9.2, and the
    // control pill on a 48px row under it.
    implicitWidth: 300 * root.s
    implicitHeight: 354 * root.s

    // --- spin: Spun's deck integrator (33⅓ rpm = 200°/s, eased spin-up/down)
    property real spinAngle: 0
    property real spinSpeed: 0
    FrameAnimation {
        running: root.active && root.visible && (root.playing || root.spinSpeed > .02)
        onTriggered: {
            const dt = Math.min(frameTime, 0.05);
            const target = root.playing ? 200 : 0;
            root.spinSpeed += (target - root.spinSpeed) * Math.min(1, dt * 2.2);
            if (root.spinSpeed < .02 && !root.playing) root.spinSpeed = 0;
            root.spinAngle = (root.spinAngle + root.spinSpeed * dt) % 360;
        }
    }

    // The circular visualiser bordering the record, under the platter so the
    // tonearm and its pivot stay on top. Centre and rim follow the platter's
    // geometry (440-unit platter at .64, record radius 205).
    MusicRadialViz {
        anchors.fill: parent
        s: root.s
        accent: root.accent
        live: root.active && root.playing
        look: root.viz
        centre: Qt.point((9.2 + 220 * .64) * root.s, (9.2 + 220 * .64) * root.s)
        rimRadius: 205 * .64 * root.s
        reach: 14 * root.s
    }

    Item {
        id: platter
        x: 9.2 * root.s
        y: 9.2 * root.s
        width: 440
        height: 440
        scale: .64 * root.s
        transformOrigin: Item.TopLeft

        // Spun's shadow: concentric faint rings, so the silhouette holds on
        // any wallpaper without a blur pass.
        Repeater {
            model: 7
            Rectangle {
                required property int index
                anchors.centerIn: parent
                anchors.verticalCenterOffset: 9
                width: 410 + index * 3; height: width; radius: width / 2
                color: "transparent"; border.width: 8; border.color: "#05000000"
            }
        }
        SpunRecord {
            anchors.centerIn: parent
            width: 410
            height: 410
            art: root.art
            angle: root.spinAngle
        }
        SpunTonearm {
            anchors.fill: parent
            engaged: root.playing
            progress: root.length > 0 ? Music.elapsed / root.length : 0
            accent: root.accent
        }
    }

    // --- the pill row: title at rest, Spun's controls on hover ------------
    readonly property bool showControls: root.hovered || pillHover.hovered
    Item {
        x: 50 * root.s
        y: 302 * root.s
        width: 200 * root.s
        height: 48 * root.s

        Column {
            anchors.centerIn: parent
            width: parent.width + 80 * root.s
            spacing: 1 * root.s
            opacity: root.showControls ? 0 : 1
            Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: Music.title
                color: root.ink
                elide: Text.ElideRight
                font.pixelSize: 15 * root.s
                font.weight: Font.DemiBold
                style: Text.Raised
                styleColor: "#40000000"
            }
            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                visible: text.length > 0
                text: Music.artist
                color: root.dim
                elide: Text.ElideRight
                font.pixelSize: 12 * root.s
            }
        }

        Rectangle {
            id: pill
            anchors.fill: parent
            radius: height / 2
            color: "#1d2024"
            opacity: root.showControls ? 1 : 0
            visible: opacity > 0.01
            Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
            HoverHandler { id: pillHover }

            component PillButton: Rectangle {
                id: pb
                property string glyph: ""
                property bool filled: false
                property bool can: true
                signal act
                width: (filled ? 48 : 44) * root.s
                height: 40 * root.s
                radius: height / 2
                anchors.verticalCenter: parent ? parent.verticalCenter : undefined
                opacity: pb.can ? 1 : 0.4
                color: pb.filled ? (pbHover.hovered ? Qt.lighter(root.accent, 1.08) : root.accent)
                     : (pbHover.hovered ? Qt.rgba(1, 1, 1, 0.10) : "transparent")
                scale: pbTap.pressed ? 0.92 : 1
                Behavior on scale { NumberAnimation { duration: 120 } }
                GlyphIcon {
                    anchors.centerIn: parent
                    width: (pb.filled ? 22 : 18) * root.s
                    height: width
                    name: pb.glyph
                    color: pb.filled ? "#111316" : "#e6e8ea"
                }
                HoverHandler { id: pbHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { id: pbTap; enabled: pb.can; onTapped: pb.act() }
            }

            Row {
                anchors.centerIn: parent
                height: parent.height
                spacing: 6 * root.s
                PillButton {
                    glyph: "prev"
                    can: root.player !== null && root.player.canGoPrevious
                    onAct: root.player.previous()
                }
                PillButton {
                    glyph: root.playing ? "pause" : "play"
                    filled: true
                    can: root.player !== null && root.player.canTogglePlaying
                    onAct: Media.toggle()
                }
                PillButton {
                    glyph: "next"
                    can: root.player !== null && root.player.canGoNext
                    onAct: root.player.next()
                }
            }
        }
    }
}
