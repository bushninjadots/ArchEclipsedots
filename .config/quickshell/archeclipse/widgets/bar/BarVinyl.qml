import QtQuick
import QtQuick.Effects
import Quickshell.Widgets
import Quickshell.Services.Mpris
import qs.theme
import qs.services

// Half-cut record that slides out from under the bar while a track plays
// (Settings -> Bar -> Music: "Vinyl"). The upper half stays tucked under the
// bar; the lower half shows below the music widget:
//   - a record's shape in the bar's own material (frame fill + rim, or the
//     no-frame surface), so it follows the bar's dynamic colour; the album
//     art is its label;
//   - spins while playing, eases to a stop on pause;
//   - an accent arc along the rim follows the track position;
//   - a glass capsule of controls (previous / play-pause / next) sits on
//     the rim; hovering shows the title and artist.
// Click the label to open the player island, wheel to skip.
//
// The host positions it: (anchorX, anchorY) = the point on the bar's inner
// edge it hangs from. It reports its visible rect for the input mask.
Item {
    id: root

    property real anchorX: 0
    property real anchorY: 0
    property bool topBar: Settings.barOrientation
    // Host says whether it may show at all (bar up, no island open, …).
    property bool allowed: true
    // Width of what it hangs from (music widget / pill): with size "match"
    // the record spans it, so it reads as part of that widget.
    property real matchWidth: 136

    readonly property var player: BarWidgets.firstPlayable
    readonly property bool hasTrack: !!root.player && (root.player.trackTitle ?? "") !== ""
    readonly property bool playing: !!root.player && root.player.playbackState === MprisPlaybackState.Playing
    // When to be out (Settings.barVinylMode):
    //   track   — whenever a track is loaded
    //   playing — while playing; tucks away 4 s after a pause (so a quick
    //             pause/resume doesn't make it bob)
    //   peek    — slides out on play / track change for 6 s, then tucks
    //             away; hovering keeps it out
    property bool _lingering: false
    property bool _peeking: false
    readonly property bool _modeWants: Settings.barVinylMode === "track" ? true
        : Settings.barVinylMode === "peek" ? (root._peeking || hoverArea.hovered)
        : (root.playing || root._lingering)
    readonly property bool wanted: Settings.barVinyl && root.allowed && root.hasTrack && root._modeWants
    onPlayingChanged: {
        if (root.playing) {
            lingerTimer.stop();
            root._lingering = false;
            root.peek();
        } else {
            root._lingering = true;
            lingerTimer.restart();
        }
    }
    readonly property string _trackKey: (root.player?.trackTitle ?? "") + "|" + (root.player?.trackArtist ?? "")
    on_TrackKeyChanged: if (root.playing) root.peek()
    function peek() {
        root._peeking = true;
        peekTimer.restart();
    }
    Timer {
        id: lingerTimer
        interval: 4000
        onTriggered: root._lingering = false
    }
    Timer {
        id: peekTimer
        interval: 6000
        onTriggered: root._peeking = false
    }
    readonly property real d: {
        const want = Settings.barVinylSize > 0 ? Settings.barVinylSize : root.matchWidth;
        return Math.round(Math.max(96, Math.min(180, Number.isFinite(want) ? want : 136)));
    }
    // How far it hangs out of the bar (half the record + the controls lip).
    readonly property real reach: root.d / 2 + 6

    // Slide: 0 = tucked under the bar, 1 = out.
    // Out: a soft spring; in: a smooth tuck (no bounce on the way back).
    property real out: 0
    onWantedChanged: root._slide()
    Component.onCompleted: root._slide()
    function _slide() {
        slide.stop();
        slide.to = root.wanted ? 1 : 0;
        slide.duration = root.wanted ? 560 : 420;
        slide.easing.type = root.wanted ? Easing.OutBack : Easing.InOutCubic;
        slide.easing.overshoot = 1.15;
        slide.start();
    }
    NumberAnimation {
        id: slide
        target: root
        property: "out"
    }
    visible: root.out > 0.01
    opacity: Math.max(0, Math.min(1, root.out * 1.6))

    // The visible window below the bar edge.
    x: root.anchorX - root.d / 2 - 10
    y: root.topBar ? root.anchorY : root.anchorY - root.reach * root.out
    width: root.d + 20
    height: root.reach * root.out + 4
    clip: true

    // ---- spin: integrate a speed that eases toward 0 / cruise ----
    property real angle: 0
    property real speed: 0          // deg per second
    readonly property real cruise: 360 / 3.2
    FrameAnimation {
        running: root.visible
        onTriggered: {
            const target = root.playing ? root.cruise : 0;
            root.speed += (target - root.speed) * Math.min(1, frameTime * 2.4);
            if (Math.abs(root.speed) > 0.05)
                root.angle = (root.angle + root.speed * frameTime) % 360;
        }
    }

    // ---- progress (MPRIS position only updates when asked) ----
    property real progress: 0
    Timer {
        interval: 1000
        repeat: true
        running: root.visible && root.playing
        triggeredOnStart: true
        onTriggered: {
            const p = root.player;
            if (!p)
                return;
            p.positionChanged();
            root.progress = p.length > 0 ? Math.max(0, Math.min(1, p.position / p.length)) : 0;
        }
    }

    readonly property bool hovered: hoverArea.hovered

    // The bar's material (see plate below). Kept fairly opaque so the art
    // and controls stay readable over windows.
    readonly property color discFill: {
        const c = ShellFrame.enabled ? ShellFrame.fill
            : Qt.color(Settings.barSurfaceStyle === "glass" ? Theme.rgba(Theme.background, 0.45)
                : Settings.barSurfaceStyle === "outline" ? Theme.rgba(Theme.background, 0.12) : Theme.surface);
        return Qt.rgba(c.r, c.g, c.b, Math.max(0.82, c.a));
    }
    readonly property color discRim: ShellFrame.enabled && ShellFrame.borderWidth > 0 ? ShellFrame.borderA
        : Settings.barSurfaceStyle === "outline" ? Theme.accent : Theme.rgba(Theme.foreground, 0.16)

    // ---- the record ----
    Item {
        id: disc
        width: root.d
        height: root.d
        x: 10
        // Centre sits on the bar edge; it slides from fully tucked.
        y: root.topBar ? -root.d / 2 - (1 - root.out) * root.d / 2 : root.height - root.d / 2 + (1 - root.out) * root.d / 2

        RectangularShadow {
            anchors.fill: parent
            radius: width / 2
            blur: 20
            spread: -4
            offset.y: root.topBar ? 6 : -6
            color: Qt.rgba(0, 0, 0, 0.35)
        }

        // The disc is the bar's own material — frame fill + rim in frame
        // mode, the surface plate otherwise — so it follows the bar's colour
        // (wallpaper / album / custom) instead of looking like real vinyl.
        Rectangle {
            id: plate
            anchors.fill: parent
            radius: width / 2
            color: root.discFill
            border.width: ShellFrame.enabled ? Math.max(1, ShellFrame.borderWidth) : (Settings.barSurfaceStyle === "outline" ? 1.5 : 1)
            border.color: root.discRim
        }
        // A few soft grooves: just enough to read as a record.
        Canvas {
            id: grooves
            anchors.fill: parent
            antialiasing: true
            property color tone: Theme.accent
            onToneChanged: requestPaint()
            onWidthChanged: requestPaint()
            onPaint: {
                const ctx = getContext("2d");
                ctx.reset();
                const c = width / 2;
                for (const f of [0.5, 0.62, 0.74, 0.86]) {
                    ctx.strokeStyle = Qt.rgba(grooves.tone.r, grooves.tone.g, grooves.tone.b, f === 0.74 ? 0.16 : 0.08);
                    ctx.lineWidth = 1;
                    ctx.beginPath();
                    ctx.arc(c, c, c * f, 0, Math.PI * 2);
                    ctx.stroke();
                }
            }
        }

        // The label (album art) is what turns.
        Item {
            id: turning
            anchors.centerIn: parent
            width: label.width
            height: width
            rotation: root.angle

            ClippingRectangle {
                id: label
                anchors.centerIn: parent
                width: root.d * 0.42
                height: width
                radius: width / 2
                color: Theme.surfaceActive
                Image {
                    anchors.fill: parent
                    source: root.player?.trackArtUrl ?? ""
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    smooth: true
                    mipmap: true
                    sourceSize.width: 256
                    sourceSize.height: 256
                    visible: status === Image.Ready
                }
                Text {
                    anchors.centerIn: parent
                    visible: (root.player?.trackArtUrl ?? "") === ""
                    text: "\u{F075A}"
                    color: Theme.accent
                    font.family: Theme.fontFamily
                    font.pixelSize: label.width * 0.42
                }
            }
        }
        // Label ring + spindle in the bar's colours.
        Rectangle {
            anchors.centerIn: parent
            width: label.width + 4
            height: width
            radius: width / 2
            color: "transparent"
            border.width: 2
            border.color: Theme.rgba(Theme.accent, 0.55)
        }
        Rectangle {
            anchors.centerIn: parent
            width: Math.max(6, root.d * 0.05)
            height: width
            radius: width / 2
            color: root.discFill
            border.width: 1
            border.color: root.discRim
        }

        // Progress arc along the rim (visible half only matters).
        Canvas {
            id: arc
            anchors.fill: parent
            antialiasing: true
            property real p: root.progress
            property color tone: Theme.accent
            onPChanged: requestPaint()
            onToneChanged: requestPaint()
            onWidthChanged: requestPaint()
            onPaint: {
                const ctx = getContext("2d");
                ctx.reset();
                const c = width / 2, R = c + 0.5 - 3;
                // The visible half: the lower one for a top bar (180° → 0°
                // through the bottom, i.e. anticlockwise on a y-down canvas),
                // the upper one for a bottom bar (180° → 360°, clockwise).
                const ccw = root.topBar;
                const end = f => ccw ? Math.PI - Math.PI * f : Math.PI + Math.PI * f;
                ctx.lineCap = "round";
                ctx.lineWidth = 2.5;
                ctx.strokeStyle = Qt.rgba(1, 1, 1, 0.08);
                ctx.beginPath();
                ctx.arc(c, c, R, Math.PI, end(1), ccw);
                ctx.stroke();
                if (arc.p <= 0)
                    return;
                ctx.strokeStyle = arc.tone;
                ctx.beginPath();
                ctx.arc(c, c, R, Math.PI, end(arc.p), ccw);
                ctx.stroke();
            }
        }

        // Label: click opens the player island.
        MouseArea {
            anchors.centerIn: parent
            width: label.width
            height: label.height
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                if (BarState.state === "player")
                    BarState.deactivate("player");
                else
                    BarState.activate("player", 0);
            }
        }
    }

    // ---- controls capsule on the rim ----
    Rectangle {
        id: controls
        anchors.horizontalCenter: parent.horizontalCenter
        y: root.topBar ? disc.y + root.d - height / 2 - 8 : disc.y + 8 - height / 2
        width: ctlRow.implicitWidth + 14
        height: 26
        radius: 13
        color: Theme.rgba(Theme.background, 0.82)
        border.width: 1
        border.color: Theme.rgba(Theme.accent, root.hovered ? 0.6 : 0.3)
        opacity: root.hovered ? 1 : 0.85
        Behavior on opacity {
            NumberAnimation { duration: 160 }
        }
        Row {
            id: ctlRow
            anchors.centerIn: parent
            spacing: 4
            Repeater {
                model: [
                    { icon: "\u{F04AE}", act: "prev", big: false },
                    { icon: root.playing ? "\u{F03E4}" : "\u{F040A}", act: "toggle", big: true },
                    { icon: "\u{F04AD}", act: "next", big: false }
                ]
                delegate: Rectangle {
                    required property var modelData
                    width: modelData.big ? 22 : 20
                    height: width
                    radius: width / 2
                    anchors.verticalCenter: parent.verticalCenter
                    color: modelData.big ? Theme.accent : (cm.containsMouse ? Theme.rgba(Theme.foreground, 0.12) : "transparent")
                    scale: cm.pressed ? 0.85 : (cm.containsMouse ? 1.08 : 1)
                    Behavior on scale {
                        NumberAnimation { duration: 140; easing.type: Easing.OutBack; easing.overshoot: 2 }
                    }
                    Text {
                        anchors.centerIn: parent
                        text: modelData.icon
                        color: modelData.big ? Theme.background : Theme.fg
                        font.family: Theme.fontFamily
                        font.pixelSize: modelData.big ? 14 : 13
                    }
                    MouseArea {
                        id: cm
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            const p = root.player;
                            if (!p)
                                return;
                            if (modelData.act === "prev" && p.canGoPrevious)
                                p.previous();
                            else if (modelData.act === "next" && p.canGoNext)
                                p.next();
                            else if (modelData.act === "toggle")
                                p.togglePlaying();
                        }
                    }
                }
            }
        }
    }

    // ---- title / artist on hover ----
    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        y: root.topBar ? Math.max(2, controls.y - height - 4) : controls.y + controls.height + 4
        width: Math.min(root.width - 8, info.implicitWidth + 16)
        height: 20
        radius: 10
        color: Theme.rgba(Theme.background, 0.85)
        opacity: root.hovered ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity {
            NumberAnimation { duration: 180 }
        }
        Text {
            id: info
            anchors.centerIn: parent
            width: Math.min(implicitWidth, parent.width - 16)
            elide: Text.ElideRight
            text: (root.player?.trackTitle ?? "") + ((root.player?.trackArtist ?? "") !== "" ? "  ·  " + root.player.trackArtist : "")
            color: Theme.fg
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeCaption
        }
    }

    HoverHandler {
        id: hoverArea
    }
    WheelHandler {
        onWheel: event => {
            const p = root.player;
            if (!p)
                return;
            if (event.angleDelta.y > 0 && p.canGoNext)
                p.next();
            else if (event.angleDelta.y < 0 && p.canGoPrevious)
                p.previous();
        }
    }
}
