pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import qs.theme

// The shell frame (Settings -> Shell frame), a port of iNiR's Iris "surround":
// one band round the screen that the navbar pill and side panels melt into.
// widgets/frame/FrameField.qml draws it inside each bar; this holds what every
// screen's frame shares — the band and the music swell
// (iNiR IrisFramePulse: bass from the shared cava feed, a fast attack and slow
// release, and a travelling phase that quickens with the level).
Singleton {
    id: root

    readonly property bool enabled: Settings.shellFrame
    readonly property real band: root.enabled ? Settings.frameThickness : 0
    readonly property real radius: root.enabled ? Settings.frameRadius : 0
    // Fillet depth where a body meets the band.
    readonly property real fuse: 14


    // --- colour ---------------------------------------------------------------
    // Album colours for "dynamic": the playing track's cover, quantised and
    // lifted to a usable saturation/lightness (iNiR's visualColor recipe).
    readonly property var player: {
        const list = Mpris.players.values;
        for (let i = 0; i < list.length; i++)
            if (list[i].isPlaying) return list[i];
        return list.length > 0 ? list[0] : null;
    }
    readonly property bool wantsAlbum: root.enabled
        && (Settings.frameColor === "dynamic" || (Settings.frameBorder && Settings.frameBorderColor === "dynamic"))
    ColorQuantizer {
        id: albumQuantizer
        source: root.wantsAlbum && root.player ? (root.player.trackArtUrl || "") : ""
        depth: 2
        rescaleSize: 24
    }
    function lift(c, hueShift) {
        const q = Qt.color(c);
        const hue = ((q.hslHue >= 0 ? q.hslHue : 0) + hueShift + 1) % 1;
        return Qt.hsla(hue, Math.max(0.40, Math.min(1, q.hslSaturation * 1.25)),
                       Math.max(0.50, Math.min(0.72, q.hslLightness)), 1);
    }
    readonly property var album: albumQuantizer.colors || []
    readonly property color dynamicA: root.album.length > 0 ? root.lift(root.album[0], 0) : root.lift(Theme.accent, 0)
    readonly property color dynamicB: root.album.length > 1 ? root.lift(root.album[1], 0)
        : root.lift(root.album.length > 0 ? root.album[0] : Theme.accent, 0.14)

    // Wallpaper colours: the current wallpaper image itself, quantised. The
    // picker keeps ~/.cache/current_wallpaper as a symlink, so resolve it
    // (a new target is a new image) whenever the theme retints — that is the
    // moment a wallpaper changed — and on a slow fallback tick.
    readonly property bool wantsWallpaper: root.enabled
        && (Settings.frameColor === "wallpaper" || (Settings.frameBorder && Settings.frameBorderColor === "wallpaper"))
    property string wallpaperPath: ""
    Process {
        id: wallProc
        command: ["sh", "-c", "readlink -f \"$HOME/.cache/current_wallpaper\" 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                const p = text.trim();
                if (p.length > 0 && /\.(png|jpe?g|webp|bmp|gif)$/i.test(p))
                    root.wallpaperPath = p;
            }
        }
    }
    function refreshWallpaper() { if (root.wantsWallpaper) wallProc.running = true; }
    onWantsWallpaperChanged: root.refreshWallpaper()
    Component.onCompleted: root.refreshWallpaper()
    Connections {
        target: Theme
        function onAccentChanged() { root.refreshWallpaper(); }
    }
    Timer {
        interval: 30000
        repeat: true
        running: root.wantsWallpaper
        onTriggered: root.refreshWallpaper()
    }
    ColorQuantizer {
        id: wallQuantizer
        source: root.wantsWallpaper && root.wallpaperPath.length > 0 ? "file://" + root.wallpaperPath : ""
        depth: 3
        rescaleSize: 64
    }
    // The wallpaper's most colourful entries win over its greys, lifted the
    // same way the album colours are.
    readonly property var wallColors: {
        const list = (wallQuantizer.colors || []).map(c => Qt.color(c));
        list.sort((a, b) => b.hslSaturation * (1 - Math.abs(b.hslLightness - 0.5))
                          - a.hslSaturation * (1 - Math.abs(a.hslLightness - 0.5)));
        return list;
    }
    readonly property color wallpaperA: root.wallColors.length > 0 ? root.lift(root.wallColors[0], 0) : root.lift(Theme.accent, 0)
    readonly property color wallpaperB: root.wallColors.length > 1 ? root.lift(root.wallColors[1], 0)
        : root.lift(root.wallColors.length > 0 ? root.wallColors[0] : Theme.accent, 0.14)

    function source(mode, custom) {
        if (mode === "accent") return Qt.color(Theme.accent);
        if (mode === "dynamic") return root.dynamicA;
        if (mode === "wallpaper") return root.wallpaperA;
        if (mode === "custom") return Qt.color(custom);
        return Qt.color(Theme.foreground);
    }
    // The band's (and, in frame mode, every pill's) fill: the bar background
    // with frameTint % of the chosen colour (100 = exactly that colour), at
    // the frame's own opacity — not the shell's Interface opacity, which at a
    // low setting washed a chosen colour out to nothing.
    readonly property color fillTarget: {
        const bg = Qt.color(Theme.background);
        const a = Settings.frameOpacity / 100;
        if (Settings.frameColor === "surface")
            return Qt.rgba(bg.r, bg.g, bg.b, a);
        const c = root.source(Settings.frameColor, Settings.frameCustomColor);
        const t = Settings.frameTint / 100;
        return Qt.rgba(bg.r + (c.r - bg.r) * t, bg.g + (c.g - bg.g) * t, bg.b + (c.b - bg.b) * t, a);
    }
    // The border's two gradient stops (equal unless dynamic).
    readonly property color borderTargetA: Settings.frameBorderColor === "subtle"
        ? Qt.rgba(Qt.color(Theme.foreground).r, Qt.color(Theme.foreground).g, Qt.color(Theme.foreground).b, 0.18)
        : root.source(Settings.frameBorderColor, Settings.frameBorderCustom)
    readonly property color borderTargetB: Settings.frameBorderColor === "dynamic" ? root.dynamicB
        : Settings.frameBorderColor === "wallpaper" ? root.wallpaperB : root.borderTargetA
    readonly property real borderWidth: root.enabled && Settings.frameBorder ? Settings.frameBorderWidth : 0

    // Eased so a new cover or a settings change fades rather than snaps.
    property color fill: root.fillTarget
    property color borderA: root.borderTargetA
    property color borderB: root.borderTargetB
    Behavior on fill { ColorAnimation { duration: 600; easing.type: Easing.OutCubic } }
    Behavior on borderA { ColorAnimation { duration: 600; easing.type: Easing.OutCubic } }
    Behavior on borderB { ColorAnimation { duration: 600; easing.type: Easing.OutCubic } }

    // A dynamic border's gradient travels round the screen: slowly at rest,
    // with the music's own phase while it plays.
    property real drift: 0
    readonly property bool flowing: root.borderWidth > 0
        && (Settings.frameBorderColor === "dynamic" || Settings.frameBorderColor === "wallpaper")
        && Settings.animationsEnabled
    Timer {
        interval: 66
        repeat: true
        running: root.flowing && !root.claims
        onTriggered: root.drift = (root.drift + 0.012) % 6283.185
    }
    readonly property real borderPhase: root.drift + root.phase

    // --- music swell ----------------------------------------------------------
    readonly property bool playing: {
        const list = Mpris.players.values;
        for (let i = 0; i < list.length; i++)
            if (list[i].isPlaying) return true;
        return false;
    }
    readonly property bool musicActive: root.enabled && Settings.frameMusic && Settings.animationsEnabled
    readonly property real strength: Math.max(0.5, Math.min(3, Settings.frameMusicStrength / 100))
    readonly property real reach: 18 * root.strength
    property real level: 0
    property real phase: 0
    // left, top, right, bottom — the order the shader reads.
    readonly property vector4d amplitudes: {
        const e = Settings.frameMusicEdges;
        const a = root.level * root.reach;
        return Qt.vector4d(e !== "horizontal" ? a : 0, e !== "sides" ? a : 0,
                           e !== "horizontal" ? a : 0, e !== "sides" ? a : 0);
    }

    // The organic attach: with the music the pill and side panels bulge into
    // the band (bodySwell), and the top band rises under the pill (topSwell),
    // whatever edges the band itself swells on.
    readonly property real bodySwell: root.level * root.reach * 0.9
    readonly property real topSwell: root.level * root.reach * 1.3

    readonly property bool claims: root.musicActive && root.playing
    onClaimsChanged: AudioBars.setActive("shell-frame", root.claims)
    onMusicActiveChanged: if (!root.musicActive) { root.level = 0; root.phase = 0; }

    FrameAnimation {
        running: root.musicActive && (root.claims || root.level > 0.002)
        onTriggered: {
            const pts = AudioBars.levels || [];
            const n = Math.min(4, pts.length);
            let bass = 0;
            for (let i = 0; i < n; i++)
                bass += Number(pts[i] || 0);
            bass = n > 0 ? Math.min(1, Math.sqrt(bass / n) * 1.4) : 0;
            if (!root.claims)
                bass = 0;
            const dt = Math.min(0.05, frameTime);
            const rate = bass > root.level ? 18 : 3.2;
            root.level += (bass - root.level) * Math.min(1, rate * dt);
            if (root.level < 0.002 && !root.claims)
                root.level = 0;
            root.phase = (root.phase + dt * (0.6 + 2.4 * root.level)) % 6283.185;
        }
    }
}
