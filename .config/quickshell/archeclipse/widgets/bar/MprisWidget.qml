import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import qs.services
import qs.theme

// MPRIS music player for the bar pill, ported from ryoku's qsbar
// MprisWidget + MprisArtwork (GPL-3) with the ryoku ties removed:
//   - `shell.services` (Perf/theme ink) -> qs.theme Theme singleton
//   - TooltipMixin -> dropped (the marquee already shows the track)
//   - IconText -> plain Text (Theme.fontFamily carries the NFP glyphs)
//   - MprisSelect.qml -> inlined ghost-filtering player pick below
//   - MprisArtwork.qml -> inlined artwork fallback probe below
//   - ryoku's MprisPanel toggle -> the shell's own PlayerIsland via
//     BarState.activate("player") (wired by the host pill in DefaultBar)
//
// Two modes, both sized to Theme.barContentHeight so the pill never
// overflows the bar row:
//   - compact (default): artwork thumb, transport buttons, marquee title,
//     animated equalizer bars
//   - full (host sets fullMode while hovered): spinning vinyl mark,
//     centered real-audio waveform from cava (optional — rests if cava
//     is not installed), transport state mark
// All colors come from the cwal-driven Theme so the widget re-themes
// with the wallpaper like the rest of the shell.

Item {
    id: root

    // Host-driven: full (vinyl + waveform) mode while the pill is hovered.
    property bool fullMode: false
    readonly property bool motionAllowed: Settings.animationsEnabled

    // Theme colors (string form) resolved to real colors once — the EQ
    // canvas and accent glyphs tint off the shell accent.
    readonly property color contentColor: Theme.fg
    readonly property color accentColor: Theme.accent

    implicitWidth: active
        ? ((fullMode ? fullRow.implicitWidth : defaultRow.implicitWidth) + 4)
        : idleNote.implicitWidth
    implicitHeight: Theme.barContentHeight

    // ---- player selection (inlined MprisSelect.qml ghost filtering) ----
    // playerctld proxies freeze as "Playing" after their player quits and
    // dead entries report Stopped with no metadata — treat both as no player.
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

    readonly property string trackLabel: {
        if (!player)
            return "";
        var t = player.trackTitle || "";
        var a = player.trackArtist || "";
        return a ? t + "  ·  " + a : t;
    }

    onPlayerChanged: artwork.refresh()

    // ---- artwork (inlined MprisArtwork.qml port) ----
    // Quickshell exposes most artwork directly through trackArtUrl. Players
    // that omit mpris:artUrl but publish a stream URL (notably cliamp) get
    // a YouTube thumbnail derived from playerctl metadata — no helper
    // script or downloaded cache file.
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
        readonly property bool ready: source !== ""

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

    // ---- compact-mode equalizer bar heights (0.0 - 1.0) ----
    property real barH1: 0.08
    property real barH2: 0.08
    property real barH3: 0.08

    SequentialAnimation {
        id: anim1
        running: root.playing && !root.fullMode && root.motionAllowed
        loops: Animation.Infinite
        NumberAnimation { target: root; property: "barH1"; to: 0.85; duration: 220; easing.type: Easing.InOutSine }
        NumberAnimation { target: root; property: "barH1"; to: 0.18; duration: 300; easing.type: Easing.InOutSine }
        NumberAnimation { target: root; property: "barH1"; to: 0.70; duration: 260; easing.type: Easing.InOutSine }
        NumberAnimation { target: root; property: "barH1"; to: 0.10; duration: 280; easing.type: Easing.InOutSine }
    }
    SequentialAnimation {
        id: anim2
        running: root.playing && !root.fullMode && root.motionAllowed
        loops: Animation.Infinite
        NumberAnimation { target: root; property: "barH2"; to: 0.45; duration: 310; easing.type: Easing.InOutSine }
        NumberAnimation { target: root; property: "barH2"; to: 0.92; duration: 280; easing.type: Easing.InOutSine }
        NumberAnimation { target: root; property: "barH2"; to: 0.28; duration: 340; easing.type: Easing.InOutSine }
        NumberAnimation { target: root; property: "barH2"; to: 0.65; duration: 290; easing.type: Easing.InOutSine }
    }
    SequentialAnimation {
        id: anim3
        running: root.playing && !root.fullMode && root.motionAllowed
        loops: Animation.Infinite
        NumberAnimation { target: root; property: "barH3"; to: 0.60; duration: 380; easing.type: Easing.InOutSine }
        NumberAnimation { target: root; property: "barH3"; to: 0.12; duration: 320; easing.type: Easing.InOutSine }
        NumberAnimation { target: root; property: "barH3"; to: 0.95; duration: 350; easing.type: Easing.InOutSine }
        NumberAnimation { target: root; property: "barH3"; to: 0.32; duration: 400; easing.type: Easing.InOutSine }
    }

    // drop bars to rest when paused / motion off
    ParallelAnimation {
        id: dropAnim
        NumberAnimation { target: root; property: "barH1"; to: 0.08; duration: 380; easing.type: Easing.OutCubic }
        NumberAnimation { target: root; property: "barH2"; to: 0.08; duration: 430; easing.type: Easing.OutCubic }
        NumberAnimation { target: root; property: "barH3"; to: 0.08; duration: 480; easing.type: Easing.OutCubic }
    }
    onPlayingChanged: {
        if (!playing) {
            dropAnim.restart();
            resetMuseLevels();
        }
    }
    onMotionAllowedChanged: {
        if (!motionAllowed) {
            dropAnim.stop();
            barH1 = 0.08;
            barH2 = 0.08;
            barH3 = 0.08;
            resetMuseLevels();
        }
        marqueeClip.resetMarquee();
    }
    onFullModeChanged: {
        resetMuseLevels();
        if (!fullMode)
            marqueeClip.resetMarquee();
    }

    // ---- full-mode: muse bands from cava (real audio, not a fake bounce) ----
    readonly property int museBands: 24
    property var museLevels: []

    function resetMuseLevels() {
        var rest = [];
        for (var i = 0; i < museBands; i++)
            rest.push(0.04);
        museLevels = rest;
    }

    Component.onCompleted: resetMuseLevels()

    Process {
        id: museCava
        running: root.visible && root.active && root.fullMode && root.playing && root.motionAllowed
        command: ["bash", "-c",
            "command -v cava >/dev/null 2>&1 || exit 0; " +
            "exec cava -p <(printf '%s\\n' " +
            "'[general]' 'bars = 24' 'framerate = 60' 'autosens = 1' 'sleep_timer = 0' " +
            "'[input]' 'method = pipewire' 'source = auto' " +
            "'[output]' 'method = raw' 'raw_target = /dev/stdout' " +
            "'data_format = ascii' 'ascii_max_range = 100' " +
            "'[smoothing]' 'monstercat = 0' 'waves = 0' 'noise_reduction = 20')"
        ]
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function(line) {
                if (!root.playing || !root.fullMode || !root.motionAllowed)
                    return;
                var parts = line.split(";");
                var out = [];
                for (var i = 0; i < root.museBands; i++) {
                    var value = parseInt(parts[i]);
                    out.push(isNaN(value) ? 0 : Math.min(1, value / 100));
                }
                root.museLevels = out;
            }
        }
    }

    // ---- idle: a single dim music-note (no player survived the filter) ----
    Text {
        id: idleNote
        anchors.centerIn: parent
        visible: !root.active
        text: "󰎈"   // music_note
        font.family: Theme.fontFamily
        font.pixelSize: 13
        color: Theme.muted
    }

    // ---- compact row: transport + artwork + marquee + EQ ----
    Row {
        id: defaultRow
        visible: root.active && !root.fullMode
        anchors.centerIn: parent
        spacing: 5

        // ---- prev ----
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "󰼮"
            font.family: Theme.fontFamily
            font.pixelSize: 13
            color: (root.player && root.player.canGoPrevious)
                ? Qt.rgba(root.contentColor.r, root.contentColor.g, root.contentColor.b, 0.7)
                : Qt.rgba(root.contentColor.r, root.contentColor.g, root.contentColor.b, 0.22)
            Behavior on color { ColorAnimation { duration: 150 } }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: if (root.player) root.player.previous()
            }
        }

        // ---- play / pause ----
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.playing ? "󰏤" : "󰐊"
            font.family: Theme.fontFamily
            font.pixelSize: 13
            color: root.accentColor
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: if (root.player) root.player.togglePlaying()
            }
        }

        // ---- next ----
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "󰼬"
            font.family: Theme.fontFamily
            font.pixelSize: 13
            color: (root.player && root.player.canGoNext)
                ? Qt.rgba(root.contentColor.r, root.contentColor.g, root.contentColor.b, 0.7)
                : Qt.rgba(root.contentColor.r, root.contentColor.g, root.contentColor.b, 0.22)
            Behavior on color { ColorAnimation { duration: 150 } }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: if (root.player) root.player.next()
            }
        }

        // ---- album artwork thumb (hidden when the player publishes no art) ----
        // Rounded to Theme.chipRadius via a MultiEffect alpha mask, the same
        // technique the marquee uses, so it stays seam-free on the pill.
        Item {
            id: artworkItem
            visible: artwork.ready
            width: visible ? Theme.barContentHeight : 0
            height: Theme.barContentHeight
            anchors.verticalCenter: parent.verticalCenter
            layer.enabled: true
            layer.effect: MultiEffect {
                maskEnabled: true
                maskSource: artworkMask
                maskThresholdMin: 0.5
                maskSpreadAtMin: 0.5
            }

            Image {
                anchors.fill: parent
                source: artwork.source
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                visible: artwork.ready
            }
        }

        // hidden rounded-rect alpha-mask source for the artwork (and defined
        // before the masked item's effect resolves it — ids hoist regardless)
        Item {
            id: artworkMask
            width: Theme.barContentHeight
            height: Theme.barContentHeight
            visible: false
            layer.enabled: true
            Rectangle {
                anchors.fill: parent
                radius: Theme.chipRadius
                color: "white"
            }
        }

        // hidden alpha-mask source for the marquee fade — defined BEFORE the
        // masked item so the layer.effect can resolve the id; visible:false →
        // no Row layout.
        Item {
            id: marqueeFadeMask
            width: 88
            height: Theme.barContentHeight
            visible: false
            layer.enabled: true
            Rectangle {
                anchors.fill: parent
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: "white" }
                    GradientStop { position: 0.92; color: "white" }
                    GradientStop { position: 1.0; color: "transparent" }
                }
            }
        }

        // ---- marquee title ----
        // Alpha-mask fade of the right edge: the scrolling title dissolves
        // into the real pixels behind it (no fixed colour → no seam on the
        // translucent pill). layer.enabled also clips to bounds.
        Item {
            id: marqueeClip
            width: 88
            height: Theme.barContentHeight
            anchors.verticalCenter: parent.verticalCenter
            layer.enabled: true
            layer.effect: MultiEffect {
                maskEnabled: true
                maskSource: marqueeFadeMask
                maskThresholdMin: 0.5
                maskSpreadAtMin: 0.5
            }

            Text {
                id: marqueeText
                anchors.verticalCenter: parent.verticalCenter
                text: root.trackLabel
                color: root.contentColor
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
                x: 0
                onTextChanged: marqueeClip.resetMarquee()
            }

            function resetMarquee() {
                marqueeAnim.stop();
                marqueeText.x = 0;
                if (root.visible && root.playing && !root.fullMode
                        && root.motionAllowed && marqueeText.implicitWidth > marqueeClip.width)
                    marqueeAnim.start();
            }

            Connections {
                target: root
                function onPlayingChanged() { marqueeClip.resetMarquee() }
                function onVisibleChanged() { marqueeClip.resetMarquee() }
            }

            SequentialAnimation {
                id: marqueeAnim
                loops: Animation.Infinite
                PauseAnimation { duration: 2000 }
                NumberAnimation {
                    target: marqueeText
                    property: "x"
                    to: -(marqueeText.implicitWidth - marqueeClip.width + 4)
                    duration: Math.max(100, marqueeText.implicitWidth - marqueeClip.width + 4) * 20
                    easing.type: Easing.Linear
                }
                PauseAnimation { duration: 900 }
                NumberAnimation { target: marqueeText; property: "x"; to: 0; duration: 0 }
            }
        }

        // ---- equalizer canvas ----
        Canvas {
            id: eqCanvas
            width: 16
            height: Theme.barContentHeight - 4
            anchors.verticalCenter: parent.verticalCenter

            property color tint: root.accentColor
            onTintChanged: requestPaint()

            onPaint: {
                var ctx = getContext("2d");
                ctx.clearRect(0, 0, width, height);

                var bars = [root.barH1, root.barH2, root.barH3];
                var bw = 3;
                var gap = 2;
                var totalW = bars.length * bw + (bars.length - 1) * gap;
                var startX = (width - totalW) / 2;
                var maxH = height - 1;
                var r = bw / 2;

                ctx.fillStyle = eqCanvas.tint;

                for (var i = 0; i < bars.length; i++) {
                    var bh = Math.max(r * 2, bars[i] * maxH);
                    var x = startX + i * (bw + gap);
                    var y = height - bh;

                    ctx.beginPath();
                    ctx.moveTo(x + r, y);
                    ctx.lineTo(x + bw - r, y);
                    ctx.arcTo(x + bw, y, x + bw, y + r, r);
                    ctx.lineTo(x + bw, y + bh - r);
                    ctx.arcTo(x + bw, y + bh, x + bw - r, y + bh, r);
                    ctx.lineTo(x + r, y + bh);
                    ctx.arcTo(x, y + bh, x, y + bh - r, r);
                    ctx.lineTo(x, y + r);
                    ctx.arcTo(x, y, x + r, y, r);
                    ctx.closePath();
                    ctx.fill();
                }
            }

            Connections {
                target: root
                function onBarH1Changed() { eqCanvas.requestPaint() }
                function onBarH2Changed() { eqCanvas.requestPaint() }
                function onBarH3Changed() { eqCanvas.requestPaint() }
            }
            Component.onCompleted: requestPaint()
        }
    }

    // ---- full row (hover): spinning vinyl · centered cava waveform ·
    // transport state ----
    Item {
        id: fullRow
        visible: root.active && root.fullMode
        anchors.centerIn: parent
        implicitWidth: fullMuseCore.width
        implicitHeight: Theme.barContentHeight

        Item {
            id: fullMuseCore
            anchors.centerIn: parent
            width: 144
            height: Theme.barContentHeight

            Row {
                id: museRow
                anchors.centerIn: parent
                spacing: 7

                Item {
                    id: vinylMark
                    width: Theme.barContentHeight
                    height: Theme.barContentHeight
                    anchors.verticalCenter: parent.verticalCenter
                    transformOrigin: Item.Center

                    Canvas {
                        id: vinylCanvas
                        anchors.fill: parent
                        antialiasing: true
                        property color tint: root.accentColor
                        onTintChanged: requestPaint()
                        onPaint: {
                            var ctx = getContext("2d");
                            ctx.clearRect(0, 0, width, height);
                            ctx.strokeStyle = tint;
                            ctx.fillStyle = tint;
                            ctx.lineWidth = 1.4;

                            var c = width / 2;
                            ctx.beginPath();
                            ctx.arc(c, c, c - 0.8, 0, Math.PI * 2);
                            ctx.stroke();
                            ctx.globalAlpha = 0.55;
                            ctx.beginPath();
                            ctx.arc(c, c, (c - 0.8) * 0.64, -0.35, 2.35);
                            ctx.stroke();
                            ctx.beginPath();
                            ctx.arc(c, c, (c - 0.8) * 0.64, 2.8, 5.5);
                            ctx.stroke();
                            ctx.globalAlpha = 1;
                            ctx.beginPath();
                            ctx.arc(c, c, 1.45, 0, Math.PI * 2);
                            ctx.fill();
                        }
                        Component.onCompleted: requestPaint()
                    }

                    RotationAnimation on rotation {
                        from: 0
                        to: 360
                        duration: 3200
                        loops: Animation.Infinite
                        running: root.visible && root.fullMode && root.playing && root.motionAllowed
                    }
                }

                Item {
                    id: museWaveform
                    width: 96
                    height: Theme.barContentHeight - 2
                    anchors.verticalCenter: parent.verticalCenter

                    Canvas {
                        id: museCanvas
                        anchors.fill: parent
                        antialiasing: true
                        property color tint: root.accentColor
                        onTintChanged: requestPaint()
                        onPaint: {
                            var ctx = getContext("2d");
                            ctx.clearRect(0, 0, width, height);
                            var levels = root.museLevels;
                            var count = root.museBands;
                            var barWidth = 2;
                            var gap = (width - count * barWidth) / (count - 1);
                            var centerY = height / 2;
                            var maxHalf = centerY - 1;
                            ctx.fillStyle = tint;

                            for (var i = 0; i < count; i++) {
                                var level = levels && levels[i] !== undefined ? levels[i] : 0.04;
                                var half = 1 + level * (maxHalf - 1);
                                var x = i * (barWidth + gap);
                                var y = centerY - half;
                                var barHeight = half * 2;
                                var radius = barWidth / 2;

                                ctx.beginPath();
                                ctx.moveTo(x + radius, y);
                                ctx.arcTo(x + barWidth, y, x + barWidth, y + radius, radius);
                                ctx.lineTo(x + barWidth, y + barHeight - radius);
                                ctx.arcTo(x + barWidth, y + barHeight, x + radius, y + barHeight, radius);
                                ctx.arcTo(x, y + barHeight, x, y + barHeight - radius, radius);
                                ctx.lineTo(x, y + radius);
                                ctx.arcTo(x, y, x + radius, y, radius);
                                ctx.closePath();
                                ctx.fill();
                            }
                        }

                        Connections {
                            target: root
                            function onMuseLevelsChanged() { museCanvas.requestPaint() }
                        }
                        Component.onCompleted: requestPaint()
                    }
                }

                Item {
                    id: transportMark
                    anchors.verticalCenter: parent.verticalCenter
                    width: 16
                    height: Theme.barContentHeight

                    Row {
                        anchors.centerIn: parent
                        spacing: 3
                        visible: root.playing
                        Repeater {
                            model: 2
                            Rectangle {
                                width: 3
                                height: 10
                                radius: 1
                                color: root.accentColor
                            }
                        }
                    }

                    Canvas {
                        id: playCanvas
                        anchors.centerIn: parent
                        width: 11
                        height: 12
                        visible: !root.playing
                        antialiasing: true
                        property color tint: root.accentColor
                        onTintChanged: requestPaint()
                        onPaint: {
                            var ctx = getContext("2d");
                            ctx.clearRect(0, 0, width, height);
                            ctx.fillStyle = tint;
                            ctx.beginPath();
                            ctx.moveTo(2, 1);
                            ctx.lineTo(width - 1, height / 2);
                            ctx.lineTo(2, height - 1);
                            ctx.closePath();
                            ctx.fill();
                        }
                        Component.onCompleted: requestPaint()
                    }
                }
            }
        }
    }
}
