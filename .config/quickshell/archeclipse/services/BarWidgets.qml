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
//   - the widget catalog and which zones each widget may live in per bar style
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
    // zones = { islands: [...], pill: [...] }; an empty list means the widget
    // cannot live in that style at all (e.g. chip is pill-only).
    readonly property var catalog: [
        {
            id: "workspaces",
            label: "Workspaces",
            icon: "\uF00A",
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
            zones: { islands: [], pill: ["rest"] }
        },
        {
            id: "weather",
            label: "Weather",
            icon: "\uF0C2",
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

    // ---- layout model ----
    function allowed(id, style, zone) {
        const e = entry(id);
        if (!e)
            return false;
        const z = e.zones ? e.zones[style] : null;
        return Array.isArray(z) && z.indexOf(zone) !== -1;
    }

    function _model(style) {
        return style === "pill" ? Settings.barLayoutPill : Settings.barLayoutIslands;
    }

    // Ordered, deduped, filtered ids for a (style, zone).
    function layout(style, zone) {
        const m = _model(style);
        const raw = (m && Array.isArray(m[zone])) ? m[zone] : [];
        const out = [];
        for (const id of raw) {
            if (typeof id !== "string")
                continue;
            if (!allowed(id, style, zone))
                continue;
            if (out.indexOf(id) !== -1)
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
        return null;
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
        ControlPanelButton {}
    }
    Component {
        id: c_weather
        WeatherButton {}
    }
    Component {
        id: c_resources
        ResourceMonitor {}
    }
    Component {
        id: c_battery
        Battery {}
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
        NetworkWidget {}
    }
    Component {
        id: c_tray
        Tray {}
    }
}
