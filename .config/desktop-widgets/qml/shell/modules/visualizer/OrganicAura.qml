pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Services.Mpris
import shell.services as Services
import "organic"
import "Singletons"

// The aura look: iNiR's Organic Edge (OrganicEdgeWidget.qml), ported to the
// desktop visualiser. The field, its motion and its shader are iNiR's own files
// (./organic); this only does what iNiR's widget does around them — resolve the
// tuning, the palette, the panel insets and the silence behaviour — reading this
// instance's VizItem instead of iNiR's Config, the shared Spectrum feed instead
// of iNiR's CavaProcess, and the archeclipse frame (ShellGeom) instead of
// iNiR's panel layout.
Item {
    id: root

    required property VizItem cfg

    readonly property var o: root.cfg.organic
    function num(key, low, high) {
        var n = Number(root.o[key]);
        return Math.max(low, Math.min(high, isFinite(n) ? n : low));
    }

    // --- which edges, and where they stand -----------------------------------
    readonly property int sides: root.cfg.auraSides
    // Inside the shell frame when there is one: the field starts at the frame's
    // inner line and turns with its corners, so the music runs off the frame.
    readonly property bool framed: ShellGeom.framed
    readonly property real frameBand: ShellGeom.frameBand
    // Without a frame, "Hug bar" keeps the old aura's behaviour: the top edge
    // starts below the navbar's reservation.
    readonly property real topGap: root.framed ? 0
        : ((root.cfg.auraBarHug && (root.sides & 1)) ? Config.auraBarsGap : 0)
    readonly property real margin: root.num("inset", 0, 160)

    // --- silence ---------------------------------------------------------------
    readonly property bool audioReactive: root.o.audioReactive !== false
    readonly property string idleMode: "" + root.o.idleMode
    readonly property real restPresence: root.num("restPresence", 0, 100) / 100
    readonly property bool sounding: Spectrum.energy > 0.03
    readonly property real audioPresence: root.audioReactive
        ? Math.min(1, (fieldLoader.item ? fieldLoader.item.energy : 0) * 1.5) : 1
    readonly property real idlePresence: root.audioReactive
        ? (root.idleMode === "hidden" ? root.audioPresence
            : root.restPresence + (1 - root.restPresence) * root.audioPresence)
        : 1
    readonly property bool frozen: Services.Perf.visualizerFrozen

    // --- palette (iNiR's visualColor/tuneColor/profiledColor, dark mode) -------
    readonly property color themePrimary: Scheme.role("primary", "#a7c080")
    readonly property color themeSecondary: Scheme.role("secondary", "#83c092")
    readonly property color themeTertiary: Scheme.role("tertiary", "#e69875")
    readonly property string palette: {
        var p = "" + (root.o.palette || "theme");
        return p === "neon" ? "vivid" : p === "ocean" ? "cool" : p === "sunset" ? "warm"
            : p === "forest" ? "wallpaper" : p;
    }

    function visualColor(value, fallback, saturationFloor, saturationBoost, hueShift) {
        var source = Qt.color(value);
        var safe = source.valid ? source : Qt.color(fallback);
        var fb = Qt.color(fallback);
        var hue = safe.hslHue >= 0 ? safe.hslHue : (fb.hslHue >= 0 ? fb.hslHue : 0);
        hue = (hue + hueShift / 360 + 1) % 1;
        var sat = Math.max(0, Math.min(1, Math.max(saturationFloor, safe.hslSaturation * saturationBoost)));
        return Qt.hsla(hue, sat, Math.max(0.45, Math.min(0.72, safe.hslLightness)), 1);
    }
    function customColor(key, fallback) {
        var c = "" + root.o[key];
        return /^#(?:[0-9a-f]{6}|[0-9a-f]{8})$/i.test(c) ? c : fallback;
    }
    function iridescentColor(offset) {
        var a = root.themePrimary;
        var hue = a.hslHue >= 0 ? a.hslHue : 0.72;
        return Qt.hsla((hue + offset) % 1, Math.max(0.55, a.hslSaturation), 0.68, 1);
    }
    function tuneColor(base) {
        var shift = root.num("hueShift", -180, 180) / 360;
        var intensity = root.num("colorIntensity", 0, 150) / 100;
        var hue = base.hslHue >= 0 ? base.hslHue : 0;
        var sat = Math.max(0, Math.min(1, base.hslSaturation * intensity));
        var light = Math.max(0.08, Math.min(0.92, 0.5 + (base.hslLightness - 0.5) * (0.82 + intensity * 0.18)));
        return Qt.hsla((hue + shift + 1) % 1, sat, light, 1);
    }
    // The wallpaper roles are matugen's, so "wallpaper" and "theme" share a
    // source here; the wallpaper profile still lifts them the way iNiR does.
    readonly property var wallpaperPalette: [
        root.visualColor(root.themePrimary, root.themePrimary, 0.30, 1.18, 0),
        root.visualColor(root.themeSecondary, root.themeSecondary, 0.28, 1.12, 0),
        root.visualColor(Qt.tint(root.themePrimary, Qt.rgba(root.themeTertiary.r, root.themeTertiary.g, root.themeTertiary.b, 0.42)),
                         root.themeTertiary, 0.30, 1.16, 0)
    ]

    // Album colours: the playing track's cover, quantised like iNiR's.
    readonly property bool wantsAlbum: root.palette === "album" || root.palette === "adaptive"
    readonly property var player: {
        var list = Mpris.players.values;
        for (var i = 0; i < list.length; i++)
            if (list[i].isPlaying) return list[i];
        return list.length > 0 ? list[0] : null;
    }
    ColorQuantizer {
        id: albumQuantizer
        source: root.wantsAlbum && root.player ? (root.player.trackArtUrl || "") : ""
        depth: 2
        rescaleSize: 24
    }
    function albumColor(index, fallback) {
        var colors = albumQuantizer.colors || [];
        if (colors.length === 0) return fallback;
        return root.visualColor(colors[Math.min(index, colors.length - 1)], fallback, 0.34, 1.24, 0);
    }
    readonly property bool albumAvailable: root.wantsAlbum && (albumQuantizer.colors || []).length > 0
    readonly property var adaptivePalette: root.albumAvailable
        ? [root.albumColor(0, root.wallpaperPalette[0]), root.albumColor(1, root.wallpaperPalette[1]),
           root.albumColor(2, root.wallpaperPalette[2])]
        : root.wallpaperPalette

    function sourceColor(i) {
        var p = root.palette === "album" ? root.adaptivePalette
            : root.palette === "theme" ? [root.themePrimary, root.themeSecondary, root.themeTertiary]
            : root.palette === "adaptive" ? root.adaptivePalette : root.wallpaperPalette;
        return p[Math.min(i, p.length - 1)];
    }
    function hueDistance(a, b) {
        if (a.hslHue < 0 || b.hslHue < 0) return 0;
        var d = Math.abs(a.hslHue - b.hslHue);
        return Math.min(d, 1 - d);
    }
    function profiledColor(i) {
        var src = root.sourceColor(i);
        var fb = i === 0 ? root.themePrimary : i === 1 ? root.themeSecondary : root.themeTertiary;
        if (root.palette === "adaptive") {
            var anchor = root.sourceColor(0);
            var shift = i > 0 && root.hueDistance(anchor, src) < 0.065 ? (i === 1 ? 26 : -32) : 0;
            return root.visualColor(src, fb, 0.36, 1.22, shift);
        }
        if (root.palette === "vivid")
            return root.visualColor(src, root.themePrimary, 0.82, 1.75, i === 0 ? -28 : i === 2 ? 34 : 0);
        if (root.palette === "cool")
            return root.visualColor(src, root.themePrimary, 0.42, 1.20, i === 0 ? -14 : i === 2 ? 12 : -4);
        if (root.palette === "warm")
            return root.visualColor(src, root.themeTertiary, 0.46, 1.28, i === 0 ? 12 : i === 2 ? -10 : 4);
        return src;
    }
    // A colour pinned in the editor's COLOR swatch wins over the palette, the
    // way it does for every other look (two stops when a gradient is set).
    readonly property color rawPrimary: root.cfg.hasCustomColor ? root.cfg.customColor
        : root.palette === "iridescent" ? root.iridescentColor(0)
        : root.palette === "custom" ? root.customColor("primaryColor", root.themePrimary)
        : root.palette === "mono" ? root.sourceColor(0) : root.profiledColor(0)
    readonly property color rawSecondary: root.cfg.gradient ? root.cfg.color2Value
        : root.cfg.hasCustomColor ? Qt.lighter(root.cfg.customColor, 1.18)
        : root.palette === "iridescent" ? root.iridescentColor(0.16)
        : root.palette === "custom" ? root.customColor("secondaryColor", root.themeSecondary)
        : root.palette === "mono" ? root.rawPrimary : root.profiledColor(1)
    readonly property color rawTertiary: root.cfg.gradient ? Qt.tint(root.cfg.customColor, Qt.rgba(root.cfg.color2Value.r, root.cfg.color2Value.g, root.cfg.color2Value.b, 0.5))
        : root.cfg.hasCustomColor ? Qt.darker(root.cfg.customColor, 1.15)
        : root.palette === "iridescent" ? root.iridescentColor(0.86)
        : root.palette === "custom" ? root.customColor("tertiaryColor", root.themeTertiary)
        : root.palette === "mono" ? root.rawPrimary : root.profiledColor(2)

    Loader {
        id: fieldLoader
        x: ((root.sides & 8) ? root.frameBand : 0) + root.margin
        y: ((root.sides & 1) ? Math.max(root.frameBand, root.topGap) : 0) + root.margin
        width: Math.max(0, root.width - x - ((root.sides & 2) ? root.frameBand : 0) - root.margin)
        height: Math.max(0, root.height - y - ((root.sides & 4) ? root.frameBand : 0) - root.margin)
        opacity: root.num("opacity", 0, 100) / 100 * root.idlePresence
        active: Config.enabled && width > 0 && height > 0
            && (!root.audioReactive || root.idleMode !== "hidden" || root.sounding || root.audioPresence > 0.003)

        sourceComponent: OrganicScreenEdge {
            id: edgeField
            active: Config.enabled
            animate: !root.frozen && (root.sounding || edgeField.energy > 0.005
                || (root.idleMode === "ambient" && root.num("idleMotion", 0, 100) > 0))
            points: root.audioReactive ? Spectrum.levels : []
            normalizationCeiling: 1
            mirroredStereo: false
            edges: Qt.vector4d((root.sides & 1) ? 1 : 0, (root.sides & 2) ? 1 : 0,
                               (root.sides & 4) ? 1 : 0, (root.sides & 8) ? 1 : 0)
            depths: {
                var d = root.num("depth", 24, 600);
                return Qt.vector4d(
                    Math.min(height * 0.45, d * root.num("topScale", 10, 200) / 100),
                    Math.min(width * 0.45, d * root.num("rightScale", 10, 200) / 100),
                    Math.min(height * 0.45, d * root.num("bottomScale", 10, 200) / 100),
                    Math.min(width * 0.45, d * root.num("leftScale", 10, 200) / 100));
            }
            span: root.num("span", 10, 100) / 100
            position: root.num("position", 0, 100) / 100
            taper: root.num("taper", 0, 50) / 100
            // In the frame the field's corners are the frame's inner corners.
            cornerRadius: root.framed ? ShellGeom.frameRadius : root.num("cornerRadius", 0, 160)
            cornerBlend: root.num("cornerBlend", 0, 100) / 100
            flowDirection: ("" + root.o.flowDirection) === "counterclockwise" ? -1 : 1
            thickness: root.num("thickness", 5, 70) / 100
            detail: root.num("detail", 0, 100) / 100
            material: Math.max(0, ["silk", "aurora", "contour", "liquid"].indexOf("" + root.o.style))
            primaryColor: root.tuneColor(root.rawPrimary)
            secondaryColor: root.tuneColor(root.rawSecondary)
            tertiaryColor: root.tuneColor(root.rawTertiary)
            colorSpeed: root.num("colorSpeed", 0, 100) / 100
            glow: root.num("glow", 0, 100) / 100
            colorMode: Math.max(0, ["flow", "spectrum", "pulse", "static"].indexOf("" + root.o.colorMode))
            effectMode: Math.max(0, ["clean", "shimmer", "echo", "prism", "bloom", "caustic", "afterglow"].indexOf("" + root.o.effectMode))
            effectStrength: root.num("effectStrength", 0, 100) / 100
            shapeMode: Math.max(0, ["flow", "ribbon", "cells", "filament"].indexOf("" + root.o.shape))
            joinConnected: ("" + root.o.joinMode) !== "separate"
            bodyOpacity: root.num("bodyOpacity", 0, 100) / 100
            crestStrength: root.num("crestStrength", 0, 150) / 100
            glowSpread: root.num("glowSpread", 0, 100) / 100
            audioRange: root.num("audioRange", 0, 150) / 100
            bassDrive: root.num("bassDrive", 0, 150) / 100
            trebleDrive: root.num("trebleDrive", 0, 150) / 100
            transientStrength: root.num("transientStrength", 0, 150) / 100
            beatGlow: root.num("beatGlow", 0, 150) / 100
            smoothing: root.num("smoothing", 0, 8)
            frequencyProfile: "" + root.o.frequencyProfile
            accentStrength: root.num("accentStrength", 0, 100) / 100
            sensitivity: root.num("sensitivity", 0, 200) / 100
            pulseStrength: root.num("pulse", 0, 150) / 100
            compression: root.num("compression", 0, 100) / 100
            motionSpeed: root.num("motionSpeed", 0, 250) / 100
            idleMotion: root.num("idleMotion", 0, 100) / 100
            attackScale: root.num("attack", 20, 250) / 100
            releaseScale: root.num("release", 20, 250) / 100
            smoothTuning: true
            tuningDuration: 150
        }
    }
}
