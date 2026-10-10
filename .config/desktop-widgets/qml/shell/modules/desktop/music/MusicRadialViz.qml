pragma ComponentBehavior: Bound
import QtQuick
import shell.services

// The vinyl design's visualiser: the shared 40-band cava feed (AudioBars) laid
// round the record's rim, mirrored left/right so the bass sits at the top and
// the spectrum meets itself at the bottom. `look` follows the Music widget's
// Visualiser option: `bars` grows rounded slivers outward from the rim, `wave`
// draws one smooth closed ring that swells with the music. Coloured by the
// album (`accent`), claimed only while live and visible, like MusicViz.
Item {
    id: viz

    property real s: 1
    property color accent: "white"
    property bool live: false
    property string look: "bars"          // bars | wave
    // The record's centre and rim (this item's px), and how far out it reaches.
    property point centre: Qt.point(width / 2, height / 2)
    property real rimRadius: 100
    property real reach: 16 * viz.s

    readonly property bool wanted: viz.live && viz.visible
    onWantedChanged: AudioBars.setActive(viz, viz.wanted)
    Component.onCompleted: AudioBars.setActive(viz, viz.wanted)
    Component.onDestruction: AudioBars.setActive(viz, false)

    // Eased levels, one per band, kept across frames (no per-frame allocation).
    property var shown: []
    property real energy: 0
    function ease() {
        const src = AudioBars.active ? AudioBars.levels : [];
        const n = AudioBars.bars;
        if (viz.shown.length !== n) {
            viz.shown = new Array(n).fill(0);
        }
        let moving = false, sum = 0;
        for (let i = 0; i < n; i++) {
            const t = Number(src[i] || 0);
            const k = t > viz.shown[i] ? 0.6 : 0.22;     // quick attack, soft fall
            viz.shown[i] += (t - viz.shown[i]) * k;
            if (Math.abs(t - viz.shown[i]) > 0.002 || viz.shown[i] > 0.004) moving = true;
            sum += viz.shown[i];
        }
        viz.energy = sum / Math.max(1, n);
        canvas.requestPaint();
        return moving;
    }
    Connections {
        target: AudioBars
        function onLevelsChanged() { if (viz.wanted) viz.ease(); }
    }
    // Settle to rest after a pause instead of freezing on the last frame.
    Timer {
        interval: 33
        repeat: true
        running: !viz.wanted && viz.energy > 0.001
        onTriggered: viz.ease()
    }

    Canvas {
        id: canvas
        anchors.fill: parent
        antialiasing: true
        renderStrategy: Canvas.Cooperative
        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            const lv = viz.shown, n = lv.length;
            if (n === 0) return;
            const cx = viz.centre.x, cy = viz.centre.y;
            const r0 = viz.rimRadius + 3 * viz.s;
            const reach = viz.reach;
            const total = n * 2;                      // mirrored round the circle
            const level = j => lv[j < n ? j : total - 1 - j];
            // 0 at the top, clockwise.
            const angleAt = j => -Math.PI / 2 + (j + 0.5) / total * Math.PI * 2;
            const a = viz.accent;

            if (viz.look === "wave") {
                const pts = [];
                for (let j = 0; j < total; j++) {
                    // a little smoothing across neighbours so it reads as a curve
                    const v = (level((j + total - 1) % total) + 2 * level(j) + level((j + 1) % total)) / 4;
                    const r = r0 + 1.5 * viz.s + v * reach;
                    const ang = angleAt(j);
                    pts.push([cx + Math.cos(ang) * r, cy + Math.sin(ang) * r]);
                }
                ctx.beginPath();
                for (let j = 0; j < total; j++) {
                    const p = pts[j], q = pts[(j + 1) % total];
                    const mx = (p[0] + q[0]) / 2, my = (p[1] + q[1]) / 2;
                    if (j === 0) {
                        const l = pts[total - 1];
                        ctx.moveTo((l[0] + p[0]) / 2, (l[1] + p[1]) / 2);
                    }
                    ctx.quadraticCurveTo(p[0], p[1], mx, my);
                }
                ctx.closePath();
                // the band between the rim and the curve, then a lit crest
                ctx.moveTo(cx + r0, cy);
                ctx.arc(cx, cy, r0, 0, Math.PI * 2, true);
                ctx.fillRule = Qt.OddEvenFill;
                ctx.fillStyle = Qt.rgba(a.r, a.g, a.b, 0.28);
                ctx.fill();
                ctx.beginPath();
                for (let j = 0; j < total; j++) {
                    const p = pts[j], q = pts[(j + 1) % total];
                    if (j === 0) {
                        const l = pts[total - 1];
                        ctx.moveTo((l[0] + p[0]) / 2, (l[1] + p[1]) / 2);
                    }
                    ctx.quadraticCurveTo(p[0], p[1], (p[0] + q[0]) / 2, (p[1] + q[1]) / 2);
                }
                ctx.closePath();
                ctx.strokeStyle = Qt.rgba(a.r, a.g, a.b, 0.95);
                ctx.lineWidth = 1.6 * viz.s;
                ctx.lineJoin = "round";
                ctx.stroke();
                return;
            }

            // bars: one rounded sliver per slot, rising outward off the rim
            const w = Math.max(1.4 * viz.s, (2 * Math.PI * r0 / total) * 0.55);
            ctx.lineCap = "round";
            ctx.lineWidth = w;
            for (let j = 0; j < total; j++) {
                const v = level(j);
                const len = Math.max(w * 0.6, v * reach);
                const ang = angleAt(j);
                const c = Math.cos(ang), s = Math.sin(ang);
                ctx.strokeStyle = Qt.rgba(a.r, a.g, a.b, 0.45 + 0.5 * Math.min(1, v * 1.4));
                ctx.beginPath();
                ctx.moveTo(cx + c * (r0 + w / 2), cy + s * (r0 + w / 2));
                ctx.lineTo(cx + c * (r0 + w / 2 + len), cy + s * (r0 + w / 2 + len));
                ctx.stroke();
            }
        }
    }
}
