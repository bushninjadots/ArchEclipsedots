pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// What is live right now, for the indicators beside the clock (after
// impasto's island): who is using the microphone, the camera or the screen
// (read from PipeWire's links — a capture stream wired to a mic / camera /
// screencast source), and a countdown timer started from the launcher
// (`!5m tea`).
Singleton {
    id: root

    // App names per kind (deduplicated, never the shell's own visualisers).
    property var mic: []
    property var camera: []
    property var screen: []
    readonly property bool micLive: root.mic.length > 0
    readonly property bool cameraLive: root.camera.length > 0
    readonly property bool screenLive: root.screen.length > 0

    // ---- PipeWire poll ----
    // pw-dump -> jq keeps only nodes (id, class, names) and links, so QML
    // parses a few KB rather than the whole graph.
    Process {
        id: pw
        command: ["bash", "-c", "pw-dump 2>/dev/null | jq -c '{n: [.[] | select(.type == \"PipeWire:Interface:Node\") | {id, c: (.info.props[\"media.class\"] // \"\"), n: (.info.props[\"node.name\"] // \"\"), a: (.info.props[\"application.name\"] // .info.props[\"node.description\"] // .info.props[\"node.name\"] // \"\"), b: (.info.props[\"application.process.binary\"] // \"\")}], l: [.[] | select(.type == \"PipeWire:Interface:Link\") | [.info[\"output-node-id\"], .info[\"input-node-id\"]]]}'"]
        stdout: StdioCollector {
            onStreamFinished: root._parse(text)
        }
    }
    Timer {
        interval: 2500
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: if (!pw.running) pw.running = true
    }
    // Our own capture streams (the bar's audio bars, cava visualisers) are
    // not "someone listening".
    readonly property var _ignore: ["quickshell", "qs", "cava"]
    function _parse(text) {
        let g;
        try {
            g = JSON.parse(text);
        } catch (e) {
            return;
        }
        const nodes = {};
        for (const n of g.n || [])
            nodes[n.id] = n;
        const mic = {}, cam = {}, scr = {};
        for (const l of g.l || []) {
            const src = nodes[l[0]], dst = nodes[l[1]];
            if (!src || !dst || !dst.c.startsWith("Stream/Input"))
                continue;
            const who = dst.a || dst.n;
            if (root._ignore.indexOf((dst.b || who).toLowerCase()) !== -1)
                continue;
            if (src.c === "Audio/Source")
                mic[who] = true;
            else if (src.c.startsWith("Video/Source") && /xdph|screencast|portal|hyprland/i.test(src.n + " " + src.a))
                scr[who] = true;
            else if (src.c.startsWith("Video/Source"))
                cam[who] = true;
        }
        const k = o => Object.keys(o).sort();
        const same = (a, b) => a.join("|") === b.join("|");
        if (!same(k(mic), root.mic)) root.mic = k(mic);
        if (!same(k(cam), root.camera)) root.camera = k(cam);
        if (!same(k(scr), root.screen)) root.screen = k(scr);
    }

    // ---- countdown timer ----
    property real timerEnd: 0          // epoch ms; 0 = none
    property real timerTotal: 0        // ms
    property string timerLabel: ""
    property real _now: Date.now()
    readonly property bool timerLive: root.timerEnd > 0
    readonly property real timerLeft: root.timerLive ? Math.max(0, root.timerEnd - root._now) : 0
    readonly property real timerProgress: root.timerTotal > 0 ? 1 - root.timerLeft / root.timerTotal : 0
    function fmtLeft(ms) {
        const s = Math.ceil(ms / 1000);
        const h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60), r = s % 60;
        const pad = v => String(v).padStart(2, "0");
        return h > 0 ? h + ":" + pad(m) + ":" + pad(r) : m + ":" + pad(r);
    }
    // "5m", "90s", "1h30m", "1:30", "25" (minutes) -> ms, or 0.
    function parseDuration(text) {
        const t = String(text || "").trim().toLowerCase();
        let m;
        if ((m = t.match(/^(\d+):(\d{1,2})(?::(\d{1,2}))?$/)))
            return m[3] !== undefined ? ((+m[1]) * 3600 + (+m[2]) * 60 + (+m[3])) * 1000 : ((+m[1]) * 60 + (+m[2])) * 1000;
        if (/^\d+(\.\d+)?$/.test(t))
            return Math.round(parseFloat(t) * 60000);
        const re = /(\d+(?:\.\d+)?)\s*(h|hr|hours?|m|min|mins|minutes?|s|sec|secs|seconds?)/g;
        let total = 0, any = false;
        while ((m = re.exec(t)) !== null) {
            any = true;
            const v = parseFloat(m[1]), u = m[2][0];
            total += u === "h" ? v * 3600000 : u === "m" ? v * 60000 : v * 1000;
        }
        // The whole text must be a duration ("5m tea" is not).
        if (t.replace(re, "").trim() !== "")
            return 0;
        return any ? Math.round(total) : 0;
    }
    function startTimer(ms, label) {
        if (!(ms > 0))
            return;
        root.timerTotal = ms;
        root.timerEnd = Date.now() + ms;
        root.timerLabel = label || "";
        root._now = Date.now();
    }
    function cancelTimer() {
        root.timerEnd = 0;
        root.timerTotal = 0;
        root.timerLabel = "";
    }
    Timer {
        interval: 250
        running: root.timerLive
        repeat: true
        onTriggered: {
            root._now = Date.now();
            if (root._now >= root.timerEnd) {
                const label = root.timerLabel;
                const total = root.fmtLeft(root.timerTotal);
                root.cancelTimer();
                Quickshell.execDetached(["bash", "-c",
                    'notify-send -u critical -a Timer "Timer done" "$1"; '
                    + 'f=/usr/share/sounds/freedesktop/stereo/complete.oga; [ -f "$f" ] && (pw-play "$f" || paplay "$f") >/dev/null 2>&1 || true',
                    "timer", label !== "" ? label + " · " + total : total + " is up"]);
            }
        }
    }
}
