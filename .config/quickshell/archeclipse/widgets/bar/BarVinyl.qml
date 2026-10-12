import QtQuick
import QtQuick.Effects
import Quickshell.Widgets
import Quickshell.Services.Mpris
import qs.theme
import qs.services

// Half-cut vinyl that slides out from under the bar while a track plays
// (Settings -> Bar -> Music: "Vinyl"). The record's upper half stays tucked
// under the bar; the lower half shows below the music widget:
//   - pressed black body with fine grooves and an accent-tinted rim,
//     the album art as its paper label, a fixed light sheen on top;
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
    readonly property bool wanted: Settings.barVinyl && root.allowed && root.hasTrack
    readonly property real d: {
        const want = Settings.barVinylSize > 0 ? Settings.barVinylSize : root.matchWidth;
        return Math.round(Math.max(96, Math.min(180, Number.isFinite(want) ? want : 136)));
    }
    // How far it hangs out of the bar (half the record + the controls lip).
    readonly property real reach: root.d / 2 + 6

    // Slide: 0 = tucked under the bar, 1 = out.
    property real out: root.wanted ? 1 : 0
    Behavior on out {
        NumberAnimation { duration: 520; easing.type: Easing.OutBack; easing.overshoot: 1.1 }
    }
    visible: root.out > 0.01

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
            color: Qt.rgba(0, 0, 0, 0.55)
        }

        Item {
            id: turning
            anchors.fill: parent
            rotation: root.angle

            Canvas {
                id: body
                anchors.fill: parent
                antialiasing: true
                renderTarget: Canvas.Image
                property color rim: Theme.accent
                onRimChanged: requestPaint()
                onWidthChanged: requestPaint()
                onPaint: {
                    const ctx = getContext("2d");
                    ctx.reset();
                    const c = width / 2, R = c - 1;
                    // Body.
                    ctx.beginPath();
                    ctx.arc(c, c, R, 0, Math.PI * 2);
                    const g = ctx.createRadialGradient(c, c, 0, c, c, R);
                    g.addColorStop(0, "#15161b");
                    g.addColorStop(0.5, "#1a1b21");
                    g.addColorStop(0.93, "#0f1014");
                    g.addColorStop(1, "#202128");
                    ctx.fillStyle = g;
                    ctx.fill();
                    // Grooves: fine rings, a little irregular.
                    let seed = 7;
                    const rnd = () => (seed = (seed * 16807) % 2147483647) / 2147483647;
                    for (let r = R * 0.43; r < R * 0.97; r += 1.15 + rnd() * 0.9) {
                        ctx.strokeStyle = "rgba(190,195,210," + (0.035 + rnd() * 0.05) + ")";
                        ctx.lineWidth = 0.5;
                        ctx.beginPath();
                        ctx.arc(c, c, r, 0, Math.PI * 2);
                        ctx.stroke();
                    }
                    // Track gaps.
                    for (const f of [0.52, 0.66, 0.8]) {
                        ctx.strokeStyle = "rgba(0,0,0,0.55)";
                        ctx.lineWidth = 1.6;
                        ctx.beginPath();
                        ctx.arc(c, c, R * f, 0, Math.PI * 2);
                        ctx.stroke();
                    }
                    // Accent-tinted rim.
                    ctx.strokeStyle = Qt.rgba(body.rim.r, body.rim.g, body.rim.b, 0.35);
                    ctx.lineWidth = 1.2;
                    ctx.beginPath();
                    ctx.arc(c, c, R - 0.6, 0, Math.PI * 2);
                    ctx.stroke();
                }
            }

            // Paper label = album art.
            ClippingRectangle {
                id: label
                anchors.centerIn: parent
                width: root.d * 0.38
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
            // Label ring + spindle.
            Rectangle {
                anchors.centerIn: parent
                width: label.width + 3
                height: width
                radius: width / 2
                color: "transparent"
                border.width: 1.5
                border.color: Qt.rgba(0, 0, 0, 0.5)
            }
            Rectangle {
                anchors.centerIn: parent
                width: Math.max(5, root.d * 0.035)
                height: width
                radius: width / 2
                color: "#0b0c0f"
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.18)
            }
        }

        // Fixed sheen (doesn't turn): the record spins under a lamp.
        Canvas {
            anchors.fill: parent
            antialiasing: true
            renderTarget: Canvas.Image
            onWidthChanged: requestPaint()
            onPaint: {
                const ctx = getContext("2d");
                ctx.reset();
                const c = width / 2, R = c - 1;
                ctx.beginPath();
                ctx.arc(c, c, R, 0, Math.PI * 2);
                ctx.arc(c, c, R * 0.2, 0, Math.PI * 2, true);
                const g = ctx.createConicalGradient(c, c, 0.5);
                g.addColorStop(0, "rgba(0,0,0,0)");
                g.addColorStop(0.1, "rgba(220,228,240,0.10)");
                g.addColorStop(0.16, "rgba(0,0,0,0)");
                g.addColorStop(0.55, "rgba(0,0,0,0)");
                g.addColorStop(0.62, "rgba(240,232,220,0.08)");
                g.addColorStop(0.68, "rgba(0,0,0,0)");
                g.addColorStop(1, "rgba(0,0,0,0)");
                ctx.fillStyle = g;
                ctx.fill();
            }
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
