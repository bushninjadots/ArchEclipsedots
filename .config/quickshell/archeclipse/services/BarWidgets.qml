pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.Mpris
import qs.theme
import qs.widgets.bar
import qs.widgets.bar.pill
import qs.widgets.weather

// Bar widget registry (bar layout system, Task 2).
//
// Single source of truth for:
//   - the widget catalog (label/icon, which styles a widget can live in, and
//     its original "home" section per style — used by the defaults and as the
//     editor's "send home" target);
//   - the section list per style (zones(style)) with editor labels;
//   - the layout model read (Settings.barLayoutIslands / barLayoutPill),
//     filtered to legal (id, style, zone) combos and de-duplicated;
//   - a Component factory for every (id, style, zone) the bar styles render;
//   - the shared "is a real player playing" gate used by the media widgets.
//
// Icons are Nerd Font glyphs written as \u escapes so this file stays plain
// ASCII. Labels are what the edit-mode tray actually shows.
Singleton {
    id: root

    // ---------------------------------------------------------------- catalog
    // zones = { islands: [...], pill: [...] } is the widget's HOME section(s)
    // per style (where the original layout puts it). Any widget may be placed
    // in ANY section of a style it supports; an empty list means the widget
    // cannot live in that style at all (e.g. chip is pill-only).
    //   stretch  — absorbs the slack of a fixed-width section (the original
    //              islands weather button fills the left zone).
    //   minWidth — per style: natural width for widgets that otherwise size
    //              from their parent (the islands workspace strip).
    readonly property var catalog: [
        {
            id: "workspaces",
            label: "Workspaces",
            icon: "\uF00A",
            minWidth: { islands: 260 },
            zones: { islands: ["bottom"], pill: ["rest"] }
        },
        {
            id: "clock",
            label: "Clock",
            icon: "\uF017",
            zones: { islands: ["center"], pill: ["rest", "core"] }
        },
        {
            id: "media",
            label: "Media",
            icon: "\uF001",
            zones: { islands: ["right"], pill: ["core"] }
        },
        {
            id: "bandwidth",
            label: "Bandwidth",
            icon: "\uF0AC",
            zones: { islands: ["center"], pill: ["core"] }
        },
        {
            id: "control",
            label: "Control",
            icon: "\uF013",
            zones: { islands: ["center"], pill: ["core"] }
        },
        {
            id: "chip",
            label: "Chip",
            icon: "\uF2DB",
            zones: { islands: ["center"], pill: ["rest"] }
        },
        {
            id: "weather",
            label: "Weather",
            icon: "\uF0C2",
            stretch: true,
            zones: { islands: ["left"], pill: ["detail"] }
        },
        {
            id: "resources",
            label: "Resources",
            icon: "\uF080",
            zones: { islands: ["left"], pill: ["detail"] }
        },
        {
            id: "battery",
            label: "Battery",
            icon: "\uF240",
            zones: { islands: ["right"], pill: ["detail"] }
        },
        {
            id: "brightness",
            label: "Brightness",
            icon: "\uF185",
            zones: { islands: ["right"], pill: ["detail"] }
        },
        {
            id: "volume",
            label: "Volume",
            icon: "\uF028",
            zones: { islands: ["right"], pill: ["detail"] }
        },
        {
            id: "network",
            label: "Network",
            icon: "\uF1EB",
            zones: { islands: ["right"], pill: ["detail"] }
        },
        {
            id: "tray",
            label: "Tray",
            icon: "\uF0C9",
            zones: { islands: ["right"], pill: ["detail"] }
        },
        // ---- extras (not in the original layouts; start on the shelf) ----
        {
            id: "window",
            label: "Window",
            icon: "\uF2D0",
            zones: { islands: ["left"], pill: ["core"] }
        },
        {
            id: "notifications",
            label: "Notifications",
            icon: "\uF0F3",
            zones: { islands: ["right"], pill: ["detail"] }
        },
        {
            id: "mic",
            label: "Microphone",
            icon: "\uF130",
            zones: { islands: ["right"], pill: ["detail"] }
        },
        {
            id: "caffeine",
            label: "Caffeine",
            icon: "\uF0F4",
            zones: { islands: ["right"], pill: ["detail"] }
        },
        {
            id: "recorder",
            label: "Recorder",
            icon: "\uF03D",
            zones: { islands: ["right"], pill: ["detail"] }
        },
        {
            id: "keyboard",
            label: "Keyboard",
            icon: "\uF11C",
            zones: { islands: ["right"], pill: ["detail"] }
        },
        {
            id: "screenshot",
            label: "Screenshot",
            icon: "\uF030",
            zones: { islands: ["right"], pill: ["detail"] }
        },
        {
            id: "clipboard",
            label: "Clipboard",
            icon: "\uF0EA",
            zones: { islands: ["right"], pill: ["detail"] }
        },
        {
            id: "power",
            label: "Power",
            icon: "\uF011",
            zones: { islands: ["right"], pill: ["detail"] }
        }
    ]

    function entry(id) {
        for (const e of catalog) {
            if (e.id === id)
                return e;
        }
        return null;
    }

    function label(id) {
        const e = entry(id);
        return e ? e.label : id;
    }

    function icon(id) {
        const e = entry(id);
        return e ? e.icon : "";
    }

    // ---- shared media presence (mirrors MprisWidget's ghost filtering) ----
    // playerctld proxies freeze as "Playing" after their player quits and dead
    // entries report Stopped with no metadata — treat both as no player.
    function _isReal(p) {
        if (!p)
            return false;
        const n = (p.dbusName || "") + " " + (p.identity || "");
        if (/playerctld/i.test(n))
            return false;
        if (p.playbackState === MprisPlaybackState.Stopped)
            return false;
        const hasMeta = !!(p.trackTitle && p.trackTitle.length > 0);
        return hasMeta || p.playbackState === MprisPlaybackState.Playing;
    }

    readonly property var firstPlayable: {
        const vals = Mpris.players.values;
        let paused = null;
        for (let i = 0; i < vals.length; i++) {
            const p = vals[i];
            if (!_isReal(p))
                continue;
            if (p.playbackState === MprisPlaybackState.Playing)
                return p;
            if (p.playbackState === MprisPlaybackState.Paused && paused === null)
                paused = p;
        }
        return paused;
    }

    // Compact fixed-width speed readout (3-char numeric + 1-char unit) so the
    // bandwidth cell never shifts width. Monospace font keeps it stable.
    function fmtSpeed(bps) {
        if (bps < 1000)
            return String(Math.round(bps)).padStart(3, " ") + "B";
        const kb = bps / 1024;
        if (kb < 10)
            return kb.toFixed(1) + "K";
        if (kb < 1000)
            return String(Math.round(kb)).padStart(3, " ") + "K";
        const mb = kb / 1024;
        if (mb < 10)
            return mb.toFixed(1) + "M";
        if (mb < 1000)
            return String(Math.round(mb)).padStart(3, " ") + "M";
        const gb = mb / 1024;
        if (gb < 10)
            return gb.toFixed(1) + "G";
        return String(Math.round(gb)).padStart(3, " ") + "G";
    }

    // ---- sections ----
    // Ordered sections per style, with the labels/hints the editor shows.
    //   islands: left / center / right share the bar edge row; bottom is the
    //            row beneath it (the opposite screen edge when detached).
    //   pill:    rest is the resting face; core + detail are the two rows the
    //            pill morphs into on hover.
    readonly property var sections: ({
        islands: [
            { id: "left", label: "Left", hint: "edge row, start" },
            { id: "center", label: "Center", hint: "accent capsule" },
            { id: "right", label: "Right", hint: "edge row, end" },
            { id: "bottom", label: "Bottom", hint: "full-width row" }
        ],
        pill: [
            { id: "rest", label: "Resting", hint: "always visible" },
            { id: "core", label: "Expanded", hint: "hover · top row" },
            { id: "detail", label: "Details", hint: "hover · bottom row" }
        ]
    })

    function zones(style) {
        return (root.sections[style] || []).map(z => z.id);
    }

    function zoneLabel(style, zone) {
        for (const z of (root.sections[style] || [])) {
            if (z.id === zone)
                return z.label;
        }
        return zone;
    }

    function zoneHint(style, zone) {
        for (const z of (root.sections[style] || [])) {
            if (z.id === zone)
                return z.hint;
        }
        return "";
    }

    // Original home section of a widget for a style ("" when unsupported).
    function home(id, style) {
        const e = entry(id);
        const z = e && e.zones ? e.zones[style] : null;
        return Array.isArray(z) && z.length > 0 ? z[0] : "";
    }

    // Can `id` live in the given style at all?
    function supports(id, style) {
        return root.home(id, style) !== "";
    }

    // Natural-width fallback for widgets that size from their parent.
    function minWidth(id, style) {
        const e = entry(id);
        return e && e.minWidth && e.minWidth[style] ? e.minWidth[style] : 0;
    }

    // Widgets that draw their own hover/press feedback (BarIconButton based
    // and the control button): the strip skips its shared hover glow.
    readonly property var _selfHover: ["network", "window", "notifications", "mic", "caffeine", "recorder", "power", "screenshot", "clipboard"]
    function selfHover(id) {
        return root._selfHover.indexOf(id) !== -1;
    }

    function stretches(id) {
        const e = entry(id);
        return !!(e && e.stretch);
    }

    // ---- layout model ----
    // Any widget the style supports may sit in any of its sections.
    function allowed(id, style, zone) {
        return root.supports(id, style) && root.zones(style).indexOf(zone) !== -1;
    }

    // Pill faces are distinct surfaces, so the same id may appear once per
    // face (clock in rest AND core). Islands is one surface: one of each.
    function multiPlace(style) {
        return style === "pill";
    }

    function _model(style) {
        return style === "pill" ? Settings.barLayoutPill : Settings.barLayoutIslands;
    }

    // Ordered, deduped, filtered ids for a (style, zone). For islands an id
    // claimed by an earlier section is dropped here too, so a hand-edited
    // settings file can never render the same widget twice.
    function layout(style, zone) {
        const m = _model(style);
        const zs = root.zones(style);
        const claimed = ({});
        if (!root.multiPlace(style)) {
            for (const z of zs) {
                if (z === zone)
                    break;
                const raw = (m && Array.isArray(m[z])) ? m[z] : [];
                for (const id of raw)
                    claimed[id] = true;
            }
        }
        const raw = (m && Array.isArray(m[zone])) ? m[zone] : [];
        const out = [];
        for (const id of raw) {
            if (typeof id !== "string")
                continue;
            if (!allowed(id, style, zone))
                continue;
            if (claimed[id] || out.indexOf(id) !== -1)
                continue;
            out.push(id);
        }
        return out;
    }

    // ---- component factory ----
    // Returns null for unknown/disallowed combos; callers MUST guard.
    function component(id, style, zone) {
        if (!allowed(id, style, zone))
            return null;
        if (style === "islands")
            return _islandsComponent(id);
        return _pillComponent(id);
    }

    function _islandsComponent(id) {
        if (id === "workspaces")
            return c_workspacesIslands;
        if (id === "clock")
            return c_clockIslands;
        if (id === "media")
            return c_mediaIslands;
        if (id === "bandwidth")
            return c_bandwidthIslands;
        if (id === "control")
            return c_control;
        if (id === "weather")
            return c_weather;
        if (id === "resources")
            return c_resources;
        if (id === "battery")
            return c_battery;
        if (id === "brightness")
            return c_brightness;
        if (id === "volume")
            return c_volume;
        if (id === "network")
            return c_network;
        if (id === "tray")
            return c_tray;
        if (id === "chip")
            return c_chip;
        return root._extraComponent(id);
    }

    // Extras look the same in both styles.
    function _extraComponent(id) {
        if (id === "window")
            return c_window;
        if (id === "notifications")
            return c_notifications;
        if (id === "mic")
            return c_mic;
        if (id === "caffeine")
            return c_caffeine;
        if (id === "recorder")
            return c_recorder;
        if (id === "keyboard")
            return c_keyboard;
        if (id === "power")
            return c_power;
        if (id === "screenshot")
            return c_screenshot;
        if (id === "clipboard")
            return c_clipboard;
        return null;
    }

    function _pillComponent(id) {
        if (id === "workspaces")
            return c_workspacesPill;
        if (id === "clock")
            return c_clockPill;
        if (id === "media")
            return c_mediaPill;
        if (id === "bandwidth")
            return c_bandwidthPill;
        if (id === "control")
            return c_control;
        if (id === "chip")
            return c_chip;
        if (id === "weather")
            return c_weather;
        if (id === "resources")
            return c_resources;
        if (id === "battery")
            return c_battery;
        if (id === "brightness")
            return c_brightness;
        if (id === "volume")
            return c_volume;
        if (id === "network")
            return c_network;
        if (id === "tray")
            return c_tray;
        return root._extraComponent(id);
    }

    // --- islands components ---
    Component {
        id: c_workspacesIslands
        Workspaces {}
    }
    Component {
        id: c_clockIslands
        Clock {
            hoverColor: "transparent"
        }
    }
    Component {
        id: c_mediaIslands
        MediaCell {}
    }
    Component {
        id: c_bandwidthIslands
        BandwidthText {
            spacing: 4
            hideWhenMedia: false
        }
    }

    // --- pill components ---
    Component {
        id: c_workspacesPill
        PillDots {}
    }
    Component {
        id: c_clockPill
        Clock {
            revealDate: false
            hoverColor: "transparent"
        }
    }
    Component {
        id: c_mediaPill
        PillMusic {
            player: root.firstPlayable
        }
    }
    Component {
        id: c_bandwidthPill
        BandwidthText {
            spacing: 5
            hideWhenMedia: true
        }
    }
    Component {
        id: c_chip
        PillChip {
            player: root.firstPlayable
        }
    }

    // --- shared components (identical in both styles) ---
    Component {
        id: c_control
        ControlPanelButton {
            flat: true
        }
    }
    Component {
        id: c_weather
        WeatherButton {
            flat: true
        }
    }
    Component {
        id: c_resources
        ResourceMonitor {}
    }
    Component {
        id: c_battery
        Battery {
            flat: true
        }
    }
    Component {
        id: c_brightness
        Brightness {}
    }
    Component {
        id: c_volume
        Volume {}
    }
    Component {
        id: c_network
        NetworkButton {}
    }
    Component {
        id: c_tray
        Tray {}
    }
    Component {
        id: c_window
        WindowTitle {}
    }
    Component {
        id: c_notifications
        NotificationsButton {}
    }
    Component {
        id: c_mic
        MicButton {}
    }
    Component {
        id: c_caffeine
        CaffeineButton {}
    }
    Component {
        id: c_recorder
        RecorderButton {}
    }
    Component {
        id: c_keyboard
        KeyboardLayoutWidget {}
    }
    Component {
        id: c_power
        PowerButton {}
    }
    Component {
        id: c_screenshot
        ScreenshotButton {}
    }
    Component {
        id: c_clipboard
        ClipboardButton {}
    }
}
