pragma Singleton

import QtQuick
import Quickshell
import qs.theme

// Hyprland window border colour that follows the shell's colour sources
// (Settings -> Frame / Hyprland -> Window Border Color): the theme accent, the
// wallpaper or the playing track's album art (both quantised by ShellFrame),
// a custom colour, or "frame" — exactly the shell frame border's colours, so
// windows and frame retint together — optionally as a two-stop gradient. Thickness stays the
// hyprland general.border_size setting.
//
// Applied live with `hyprctl eval hl.config(...)` (debounced, only when the
// colours actually change) and mirrored to config/custom/general:col.lua so a
// Hyprland reload keeps it. "default" removes that file and stops touching
// Hyprland's own border colours.
Singleton {
    id: root

    readonly property string mode: Settings.windowBorderColor
    readonly property bool active: root.mode !== "default"

    function _pair() {
        if (root.mode === "frame") {
            // Same targets the frame border eases to (not the eased value,
            // which would re-apply on every animation frame).
            if (Settings.frameBorderColor === "subtle") {
                // A muted foreground: the text colour 40% of the way out of
                // the background (a solid foreground border is too loud).
                const f = Qt.color(Theme.foreground), b = Qt.color(Theme.background);
                const m = Qt.rgba(b.r + (f.r - b.r) * 0.4, b.g + (f.g - b.g) * 0.4, b.b + (f.b - b.b) * 0.4, 1);
                return [m, m];
            }
            return [ShellFrame.borderTargetA, ShellFrame.borderTargetB];
        }
        if (root.mode === "wallpaper")
            return [ShellFrame.wallpaperA, ShellFrame.wallpaperB];
        if (root.mode === "dynamic")
            return [ShellFrame.dynamicA, ShellFrame.dynamicB];
        if (root.mode === "custom") {
            const c = Qt.color(Settings.windowBorderCustom);
            return [c, ShellFrame.lift(c, 0.10)];
        }
        const a = Qt.color(Theme.accent);
        return [a, ShellFrame.lift(a, 0.12)];
    }

    function _hex(c, alpha) {
        const h = v => Math.round(Math.max(0, Math.min(1, v)) * 255).toString(16).padStart(2, "0");
        return "rgba(" + h(c.r) + h(c.g) + h(c.b) + h(alpha) + ")";
    }

    // Lua table for hl.config's general.col.
    readonly property string lua: {
        if (!root.active)
            return "";
        const p = root._pair();
        const ia = Math.max(0, Math.min(100, Settings.windowBorderInactive)) / 100;
        const act = Settings.windowBorderGradient
            ? '{ colors = { "' + root._hex(p[0], 1) + '", "' + root._hex(p[1], 1) + '" }, angle = 45 }'
            : '"' + root._hex(p[0], 1) + '"';
        const ina = '"' + root._hex(p[0], ia) + '"';
        return "hl.config({ general = { col = { active_border = " + act + ", inactive_border = " + ina + " } } })";
    }

    property string _applied: ""
    onLuaChanged: applyTimer.restart()
    onActiveChanged: applyTimer.restart()
    Component.onCompleted: applyTimer.restart()

    // Colours ease over ~600ms in ShellFrame; wait for them to settle.
    Timer {
        id: applyTimer
        interval: 900
        onTriggered: root.apply()
    }

    function apply() {
        const file = "$HOME/.config/hypr/config/custom/general:col.lua";
        if (!root.active) {
            // Only reload Hyprland when an override file actually existed.
            Quickshell.execDetached(["bash", "-c", `[ -f "${file}" ] && rm -f "${file}" && hyprctl reload >/dev/null 2>&1; true`]);
            root._applied = "";
            return;
        }
        if (root.lua === root._applied)
            return;
        root._applied = root.lua;
        Quickshell.execDetached(["bash", "-c",
            `mkdir -p "$HOME/.config/hypr/config/custom" && printf '%s\\n' "$1" > "${file}" && hyprctl eval "$1" >/dev/null 2>&1 || true`,
            "wb", root.lua]);
    }
}
