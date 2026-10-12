import QtQuick
import Quickshell
import Quickshell.Services.Mpris
import qs.theme
import qs.services
import qs.widgets.visualizer

// Music-reactive spectrum that rises from the bar's inner edge while a track
// plays. Inserted into Bar.qml's pill surface *before* the state stack, so it
// sits behind the content and the border appears to feed the visualiser.
//
// It never owns an analyser: it claims the shared AudioBars cava feed (the
// owner-refcounted singleton) only while it is actually drawing, so there is
// no extra process and no duplicate analysis.
Item {
    id: root

    // Live only in the pill bar style, when a visualiser style is chosen, and
    // when a real track is playing.
    // Not while an island is open (its card would sit on the bars) nor in
    // the editor. Settings -> Bar -> Visualiser picks the look or turns it off.
    readonly property bool wanted: Settings.barStyle === "pill"
        && Settings.barSpectrum !== "off"
        && root.playing
        && !BarEditState.active
        && (BarState.state === "default" || BarState.state === "recording")

    // ---- player selection (same ghost filtering as MprisWidget) ----
    // playerctld proxies freeze as "Playing" after their player quits and
    // dead entries report Stopped with no metadata — neither lights the bar.
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
        for (var i = 0; i < vals.length; i++) {
            var p = vals[i];
            if (!isReal(p))
                continue;
            if (p.playbackState === MprisPlaybackState.Playing)
                return p;
        }
        return null;
    }
    // Only genuine playback drives the spectrum — paused settles to rest.
    readonly property bool playing: player !== null

    // Ease the whole layer in/out so the spectrum doesn't pop on track change.
    visible: opacity > 0.001
    opacity: wanted ? 1 : 0
    Behavior on opacity {
        enabled: Settings.animationsEnabled
        NumberAnimation {
            duration: 420
            easing.type: Easing.OutCubic
        }
    }

    onWantedChanged: AudioBars.setActive(root, wanted)
    Component.onDestruction: AudioBars.setActive(root, false)

    // ---- smoothing: fast attack, slow release (per band) ----
    property var shown: []
    Connections {
        target: AudioBars
        enabled: root.wanted
        function onLevelsChanged() {
            const src = AudioBars.levels || [];
            const prev = root.shown.length === src.length ? root.shown : src.map(() => 0);
            root.shown = src.map((v, i) => v > prev[i] ? prev[i] + (v - prev[i]) * 0.7 : prev[i] * 0.86 + v * 0.14);
            canvas.requestPaint();
        }
    }

    // One canvas for every look. Drawn growing up from y = height (the inner
    // edge); a bottom bar flips the item so it grows down from the top.
    Canvas {
        id: canvas
        anchors.fill: parent
        opacity: Settings.barSpectrumStrength / 100
        transform: Scale {
            origin.y: canvas.height / 2
            yScale: Settings.barOrientation ? 1 : -1
        }
        property color tint: Theme.accent
        onTintChanged: requestPaint()
        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            const lv = root.shown, n = lv.length, W = width, H = height;
            if (n === 0 || W <= 0)
                return;
            const band = H * Settings.barSpectrumHeight / 100;
            const style = Settings.barSpectrum;
            const t = canvas.tint;
            const col = a => Qt.rgba(t.r, t.g, t.b, a);
            // Fade from solid at the edge to clear toward the content.
            const fade = ctx.createLinearGradient(0, H, 0, H - band);
            fade.addColorStop(0, col(0.95));
            fade.addColorStop(1, col(0.05));

            // Mirror: bass in the middle, fanning out to both ends.
            let vals = lv;
            if (style === "mirror") {
                const half = lv.slice(0, Math.ceil(n / 2));
                vals = half.slice().reverse().concat(half);
            }
            const m = vals.length;

            if (style === "wave") {
                ctx.beginPath();
                ctx.moveTo(0, H);
                const step = W / (m - 1);
                let px = 0, py = H - vals[0] * band;
                ctx.lineTo(px, py);
                for (let i = 1; i < m; i++) {
                    const x = i * step, y = H - vals[i] * band;
                    ctx.quadraticCurveTo(px, py, (px + x) / 2, (py + y) / 2);
                    px = x;
                    py = y;
                }
                ctx.lineTo(W, py);
                ctx.lineTo(W, H);
                ctx.closePath();
                ctx.fillStyle = fade;
                ctx.fill();
                return;
            }
            if (style === "glow") {
                // Soft pools of light: a few wide radial blooms whose size
                // follows the energy of their slice of the spectrum.
                const pools = 7;
                for (let p = 0; p < pools; p++) {
                    let e = 0;
                    const a = Math.floor(p * n / pools), b = Math.floor((p + 1) * n / pools);
                    for (let i = a; i < b; i++)
                        e += lv[i];
                    e /= Math.max(1, b - a);
                    const cx = W * (p + 0.5) / pools, r = band * (0.6 + e * 1.6);
                    const g = ctx.createRadialGradient(cx, H, 0, cx, H, r);
                    g.addColorStop(0, col(0.25 + e * 0.6));
                    g.addColorStop(1, col(0));
                    ctx.fillStyle = g;
                    ctx.fillRect(cx - r, H - r, r * 2, r);
                }
                return;
            }
            // bars / mirror: rounded columns.
            const gap = 2;
            const bw = Math.max(1, (W - gap * (m - 1)) / m);
            ctx.fillStyle = fade;
            for (let i = 0; i < m; i++) {
                const h = Math.max(1.5, vals[i] * band);
                const x = i * (bw + gap), y = H - h, r = Math.min(bw / 2, h / 2);
                ctx.beginPath();
                ctx.moveTo(x, H);
                ctx.lineTo(x, y + r);
                ctx.arcTo(x, y, x + r, y, r);
                ctx.lineTo(x + bw - r, y);
                ctx.arcTo(x + bw, y, x + bw, y + r, r);
                ctx.lineTo(x + bw, H);
                ctx.closePath();
                ctx.fill();
            }
        }
    }
}
