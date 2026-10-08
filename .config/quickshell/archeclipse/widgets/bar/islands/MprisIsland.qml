import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import qs.services
import qs.theme
import qs.widgets.bar.islands

// Now-playing island, ported from ryoku's qsbar MprisPanel.qml (GPL-3) with
// the ryoku ties removed (theme ink/seal/fills -> qs.theme tokens, UiText/
// IconText -> themed Text, MprisSelect/MprisArtwork -> inlined ports).
// Opens in the bar's main pill stack on the "player" state (left click on
// the navbar MprisWidget), same island pattern as PlayerIsland.
//
// Sections: NOW PLAYING header + close, the spinning disc with artwork and
// a live spectrum ring (shared AudioBars cava feed), track/artist/album,
// seekable progress with live position extrapolation, and transport.
// Ryoku's equalizer section is NOT ported: its backend (`ryoku-eq`, a
// WirePlumber filter-graph + systemd unit) does not exist on this system.
Column {
    id: root
    spacing: 0

    // Island owner passes the bar's monitor (unused visually, kept for parity).
    property string monitorName: ""

    // Expand driver: 0 -> 1 on creation unfolds the body; the Bar
    // exit driver plays 1 -> 0 on close before swapping content.
    property real expand: 0
    Component.onCompleted: {
        expand = 1;
        intro.restart();
    }

    // Stay-open behavior for a click-opened island: hover pins persistent,
    // leaving arms the reveal-out close timer; Esc and the ✕ also close.
    IslandHoverPin {
        stateName: "player"
        armOnCreation: false
    }
    IslandEscClose {
        states: ["player"]
    }

    // Claim the shared cava spectrum while the card is up.
    onVisibleChanged: AudioBars.setActive(root, visible)
    Component.onDestruction: AudioBars.setActive(root, false)

    // ---- player selection (inlined MprisSelect.qml ghost filtering, same
    // as MprisWidget) — panel and widget always agree on the active player ----
    function isProxy(p) {
        var n = (p.dbusName || "") + " " + (p.identity || "");
        return /playerctld/i.test(n);
    }
    function isReal(p) {
        if (!p)
            return false;
        if (isProxy(p))
            return false;
        if (p.playbackState === MprisPlaybackState.Stopped)
            return false;
        var hasMeta = (p.trackTitle && p.trackTitle.length > 0);
        return hasMeta || p.playbackState === MprisPlaybackState.Playing;
    }
    readonly property var player: {
        var vals = Mpris.players.values;
        var paused = null;
        for (var i = 0; i < vals.length; i++) {
            var p = vals[i];
            if (!isReal(p))
                continue;
            if (p.playbackState === MprisPlaybackState.Playing)
                return p;
            if (p.playbackState === MprisPlaybackState.Paused && paused === null)
                paused = p;
        }
        return paused;
    }
    readonly property bool active: player !== null
    readonly property bool playing: active && player.playbackState === MprisPlaybackState.Playing

    readonly property string playerName: {
        if (!player)
            return "";
        var n = player.identity || player.dbusName || "";
        return n.replace(/^org\.mpris\.MediaPlayer2\./, "");
    }

    // ---- artwork (inlined MprisArtwork.qml port, same as MprisWidget) ----
    Item {
        id: artwork
        property string fallbackUrl: ""
        // Some players (kew) publish a bare file path; Image needs a URL.
        function asUrl(u) {
            var v = String(u || "");
            return v.startsWith("/") ? "file://" + v : v;
        }
        readonly property string source: asUrl((root.player && root.player.trackArtUrl)
            ? root.player.trackArtUrl
            : fallbackUrl)

        visible: false
        width: 0
        height: 0

        function playerctlName() {
            if (!root.player)
                return "";
            return String(root.player.dbusName || "")
                .replace(/^org\.mpris\.MediaPlayer2\./, "");
        }

        function youtubeThumbnail(url) {
            var value = String(url || "").trim();
            var match = value.match(/[?&]v=([A-Za-z0-9_-]{11})/);
            if (!match)
                match = value.match(/youtu\.be\/([A-Za-z0-9_-]{11})/);
            return match ? "https://i.ytimg.com/vi/" + match[1] + "/mqdefault.jpg" : "";
        }

        function applyMetadata(raw) {
            var value = String(raw || "").trim();
            var separator = value.indexOf("|");
            var direct = separator >= 0 ? value.slice(0, separator).trim() : value;
            var pageUrl = separator >= 0 ? value.slice(separator + 1).trim() : "";
            fallbackUrl = direct || youtubeThumbnail(pageUrl);
        }

        function refresh() {
            fallbackUrl = "";
            artworkProbe.running = false;
            if (!root.player || root.player.trackArtUrl || playerctlName() === "")
                return;
            artworkRefresh.restart();
        }

        Timer {
            id: artworkRefresh
            interval: 1
            repeat: false
            onTriggered: {
                artworkProbe.command = [
                    "timeout", "2", "playerctl", "-p", artwork.playerctlName(),
                    "metadata", "--format", "{{mpris:artUrl}}|{{xesam:url}}"
                ];
                artworkProbe.running = true;
            }
        }

        Process {
            id: artworkProbe
            command: []
            stdout: StdioCollector {
                onStreamFinished: artwork.applyMetadata(this.text)
            }
        }

        Connections {
            target: root.player
            ignoreUnknownSignals: true
            function onTrackTitleChanged() { artwork.refresh() }
            function onTrackArtUrlChanged() { artwork.refresh() }
        }

        Component.onCompleted: refresh()
    }
    onPlayerChanged: artwork.refresh()

    // ---- live position ----
    // Quickshell only refreshes `position` sporadically, so we extrapolate
    // locally while playing and resync whenever the player reports a value.
    property real curPos: 0
    property real curLen: 0
    property real _lastRead: -1
    Timer {
        interval: 500
        repeat: true
        running: root.visible && root.active
        triggeredOnStart: true
        onTriggered: {
            if (!root.player)
                return;
            var p = root.player.position || 0;
            root.curLen = root.player.length || 0;
            if (Math.abs(p - root._lastRead) > 0.05) {
                root.curPos = p;
                root._lastRead = p;
            } else if (root.playing) {
                var cap = root.curLen > 0 ? root.curLen : p + 1e9;
                root.curPos = Math.min(cap, root.curPos + 0.5);
            }
        }
    }
    onPlayingChanged: _lastRead = -1   // force a resync on play/pause

    // Some players keep reporting a position past the end of the track,
    // which would read as 4:25 of a 3:42 song — clamp the readout.
    readonly property real shownPos: curLen > 0 ? Math.min(curPos, curLen) : curPos

    function fmtTime(s) {
        if (!s || s < 0)
            return "0:00";
        var m = Math.floor(s / 60);
        var sec = Math.floor(s % 60);
        return m + ":" + (sec < 10 ? "0" + sec : "" + sec);
    }

    function seekTo(fraction) {
        if (!player || !player.canSeek || curLen <= 0)
            return;
        var target = Math.max(0, Math.min(1, fraction)) * curLen;
        curPos = target;
        _lastRead = -1;
        player.position = target;
    }

    // ---- entry stagger: the card assembles rather than appearing ----
    property real inCover: 0
    property real inText: 0
    property real inControls: 0

    ParallelAnimation {
        id: intro
        NumberAnimation { target: root; property: "inCover"; from: 0; to: 1; duration: 420; easing.type: Easing.OutBack; easing.overshoot: 0.9 }
        SequentialAnimation {
            PauseAnimation { duration: 60 }
            NumberAnimation { target: root; property: "inText"; from: 0; to: 1; duration: 340; easing.type: Easing.OutCubic }
        }
        SequentialAnimation {
            PauseAnimation { duration: 110 }
            NumberAnimation { target: root; property: "inControls"; from: 0; to: 1; duration: 340; easing.type: Easing.OutCubic }
        }
    }

    // ---- the card surface ----
    Rectangle {
        width: 560
        height: col.implicitHeight + 24
        radius: Theme.radius
        color: Theme.surface

        Column {
            id: col
            anchors.fill: parent
            anchors.margins: 14
            spacing: 10

            // ---- header ----
            Item {
                width: parent.width
                height: 20

                Text {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: "NOW PLAYING"
                    color: Theme.fg
                    font.family: Theme.fontFamily
                    font.pixelSize: 13
                    font.letterSpacing: 2
                    font.weight: Font.Medium
                }
                Row {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: root.active && root.playerName !== ""
                        text: root.playerName
                        color: Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.45)
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                        font.letterSpacing: 1
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "\u2715"
                        color: closeMa.containsMouse ? Theme.accent : Theme.muted
                        font.pixelSize: 12
                        Behavior on color { ColorAnimation { duration: 120 } }
                        MouseArea {
                            id: closeMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: BarState.deactivate("player")
                        }
                    }
                }
            }

            Rectangle { width: parent.width; height: 1; color: Theme.border }

            // ---- record + track ----
            Row {
                width: parent.width
                height: 168
                spacing: 16

                // the record: art under the grooves, spectrum ring around it
                Item {
                    id: coverHost
                    width: 168
                    height: 168
                    anchors.verticalCenter: parent.verticalCenter

                    opacity: root.inCover
                    transform: Translate { x: -26 * (1 - root.inCover) }

                    readonly property real artRadius: width * 0.41
                    readonly property real barRoom: width / 2 - artRadius
                    readonly property real barWidth: Math.max(2, (2 * Math.PI * artRadius) / AudioBars.bars * 0.55)

                    // Breathe with the music: the whole record leans on the
                    // mean energy of the spectrum, not any single band.
                    readonly property real pulse: root.playing ? AudioBars.energy : 0

                    Item {
                        id: discGroup
                        anchors.centerIn: parent
                        width: coverHost.artRadius * 2
                        height: width
                        scale: 1 + coverHost.pulse * 0.05
                        Behavior on scale { SpringAnimation { spring: 4.6; damping: 0.36; mass: 0.8 } }

                        // spectrum ring
                        Repeater {
                            model: AudioBars.bars
                            delegate: Item {
                                required property int index
                                anchors.centerIn: parent
                                width: 0
                                height: 0
                                rotation: index * (360 / AudioBars.bars)
                                readonly property real level: {
                                    var lv = AudioBars.levels;
                                    return (lv && lv[index] !== undefined) ? lv[index] : 0;
                                }
                                Rectangle {
                                    anchors.bottom: parent.top
                                    anchors.bottomMargin: coverHost.artRadius + 3
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    width: coverHost.barWidth
                                    height: Math.max(2, parent.level * (coverHost.barRoom - 4))
                                    radius: width / 2
                                    antialiasing: true
                                    color: Theme.accent
                                    opacity: 0.35 + parent.level * 0.65
                                    Behavior on height { NumberAnimation { duration: 70; easing.type: Easing.OutCubic } }
                                }
                            }
                        }

                        // the disc itself: art, grooves, spindle
                        Item {
                            id: disc
                            anchors.fill: parent
                            NumberAnimation on rotation {
                                id: spin
                                from: 0
                                to: 360
                                duration: 24000
                                loops: Animation.Infinite
                                running: root.visible
                                // Pausing keeps the needle where it stopped, but
                                // Qt refuses the call on a stopped animation, so
                                // the state only exists while it runs.
                                paused: spin.running && !root.playing
                            }

                            Rectangle {
                                anchors.fill: parent
                                radius: width / 2
                                color: Theme.surfaceHover
                                border.width: 1
                                border.color: root.playing ? Theme.accent : Theme.border
                                Behavior on border.color { ColorAnimation { duration: 400 } }
                            }

                            // circular crop for the artwork: QML `clip` is a
                            // rectangle, so the round edge is a mask.
                            Rectangle {
                                id: artMask
                                anchors.fill: parent
                                anchors.margins: 1
                                radius: width / 2
                                visible: false
                                layer.enabled: true
                            }

                            Item {
                                anchors.fill: parent
                                anchors.margins: 1
                                layer.enabled: true
                                layer.effect: MultiEffect {
                                    maskEnabled: true
                                    maskSource: artMask
                                }
                                Image {
                                    id: discArt
                                    anchors.fill: parent
                                    source: artwork.source
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                    cache: true
                                    visible: status === Image.Ready
                                }
                            }

                            Text {
                                anchors.centerIn: parent
                                visible: discArt.status !== Image.Ready
                                text: "󰎈"   // music_note
                                font.family: Theme.fontFamily
                                font.pixelSize: 46
                                color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.5)
                            }

                            // grooves
                            Repeater {
                                model: [0.88, 0.74, 0.60, 0.46]
                                delegate: Rectangle {
                                    required property real modelData
                                    anchors.centerIn: parent
                                    width: parent.width * modelData
                                    height: width
                                    radius: width / 2
                                    color: "transparent"
                                    border.width: 1
                                    border.color: Qt.rgba(0, 0, 0, 0.22)
                                    antialiasing: true
                                }
                            }

                            // spindle
                            Rectangle {
                                anchors.centerIn: parent
                                width: parent.width * 0.24
                                height: width
                                radius: width / 2
                                color: Theme.surfaceHover
                                border.width: 1
                                border.color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.55)
                                Rectangle {
                                    anchors.centerIn: parent
                                    width: parent.width * 0.3
                                    height: width
                                    radius: width / 2
                                    color: Theme.border
                                }
                            }
                        }
                    }
                }

                // track, progress, transport
                Column {
                    id: infoCol
                    width: parent.width - coverHost.width - 16
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8

                    Column {
                        width: parent.width
                        spacing: 4
                        opacity: root.inText
                        transform: Translate { x: 20 * (1 - root.inText) }

                        Text {
                            width: parent.width
                            text: root.active ? (root.player.trackTitle || "Unknown") : "No song playing"
                            color: Theme.fg
                            font.family: Theme.fontFamily
                            font.pixelSize: 15
                            font.weight: Font.Medium
                            elide: Text.ElideRight
                        }
                        Text {
                            width: parent.width
                            text: root.active ? (root.player.trackArtist || "Unknown artist") : "no active player"
                            color: Theme.fgDim
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                            elide: Text.ElideRight
                        }
                        Text {
                            width: parent.width
                            visible: root.active && text !== ""
                            text: root.player ? (root.player.trackAlbum || "") : ""
                            color: Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.4)
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            elide: Text.ElideRight
                        }
                    }

                    // ---- progress ----
                    Item {
                        width: parent.width
                        height: 26
                        visible: root.active
                        opacity: root.inControls
                        transform: Translate { y: 8 * (1 - root.inControls) }

                        Rectangle {
                            id: trackBar
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.topMargin: 4
                            height: 5
                            radius: 2.5
                            color: Theme.surfaceActive
                            Rectangle {
                                id: played
                                height: parent.height
                                radius: parent.radius
                                color: Theme.accent
                                width: parent.width * (root.curLen > 0
                                    ? Math.min(1, root.curPos / root.curLen) : 0)
                                Behavior on width { NumberAnimation { duration: seekMa.pressed ? 0 : 450 } }
                            }
                            Rectangle {
                                x: played.width - width / 2
                                anchors.verticalCenter: parent.verticalCenter
                                width: seekMa.containsMouse || seekMa.pressed ? 11 : 0
                                height: width
                                radius: width / 2
                                color: Theme.accent
                                visible: root.curLen > 0
                                Behavior on width { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                            }
                        }
                        MouseArea {
                            id: seekMa
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            height: 14
                            hoverEnabled: true
                            enabled: root.player ? root.player.canSeek : false
                            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onPressed: (m) => root.seekTo(m.x / width)
                            onPositionChanged: (m) => {
                                if (pressed)
                                    root.seekTo(m.x / width);
                            }
                        }
                        Text {
                            anchors.left: parent.left
                            anchors.bottom: parent.bottom
                            text: root.fmtTime(root.shownPos)
                            color: Theme.fgDim
                            font.family: Theme.fontFamily
                            font.pixelSize: 10
                        }
                        Text {
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            text: root.fmtTime(root.curLen)
                            color: Theme.fgDim
                            font.family: Theme.fontFamily
                            font.pixelSize: 10
                        }
                    }

                    // ---- transport ----
                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 10
                        visible: root.active
                        opacity: root.inControls
                        transform: Translate { y: 12 * (1 - root.inControls) }

                        Repeater {
                            model: [
                                { action: "prev", glyph: "󰼮", primary: false, enabled: root.player ? root.player.canGoPrevious : false },
                                { action: "toggle", glyph: root.playing ? "󰏤" : "󰐊", primary: true, enabled: root.player ? root.player.canTogglePlaying : false },
                                { action: "next", glyph: "󰼬", primary: false, enabled: root.player ? root.player.canGoNext : false }
                            ]
                            delegate: Rectangle {
                                id: tb
                                required property var modelData
                                readonly property bool primary: modelData.primary
                                readonly property bool on: modelData.enabled
                                width: primary ? 38 : 30
                                height: width
                                radius: Theme.chipRadius
                                color: !on ? Theme.surface : (tbMa.containsMouse ? Theme.surfaceHover : Theme.surface)
                                border.width: 1
                                border.color: tbMa.containsMouse && on ? Theme.accent : Theme.border
                                Behavior on color { ColorAnimation { duration: 120 } }
                                Text {
                                    anchors.centerIn: parent
                                    text: tb.modelData.glyph
                                    font.family: Theme.fontFamily
                                    font.pixelSize: tb.primary ? 20 : 16
                                    color: !tb.on ? Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.25)
                                         : (tb.primary ? Theme.accent : Theme.fg)
                                }
                                MouseArea {
                                    id: tbMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    enabled: tb.on
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (!root.player)
                                            return;
                                        if (tb.modelData.action === "prev")
                                            root.player.previous();
                                        else if (tb.modelData.action === "next")
                                            root.player.next();
                                        else
                                            root.player.togglePlaying();
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Rectangle { width: parent.width; height: 1; color: Theme.border }

        }
    }
}
