pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Mirrors the subset of the quickshell settings.json
// (~/.cache/quickshell/settings/settings.json) that the bar and panels
// consume. Values are read once at startup; the settings UI remains the
// editor and this shell follows the same file throughout.
Singleton {
    id: root

    // --- simple booleans / ints / strings ---
    property bool barLock: true
    property bool barSmartHide: false
    property bool barDefault: true
    property bool barFullWidth: false
    property real revealInPressure: 250
    property real revealOutPressure: 1000
    property bool mprisVisualizer: false
    property bool barOrientation: true        // true = top

    // Navbar MPRIS widget style (persisted): false = compact player
    // (transport + marquee + EQ), true = visualizer-only (vinyl + cava
    // waveform). Toggled by right-clicking the player pill.

    // iNiR visualizer import: navbar widget style (bars / wave / off).
    // (The screen-edge border lives in the desktop-widgets visualizer now,
    // under right-click desktop -> Customize visualizer.)
    property string visualizerStyle: "bars"     // "bars" | "wave" | "off"

    // Shell frame (iNiR Iris "surround" port): a band round the whole screen
    // with rounded inner corners that the navbar pill and side panels melt
    // into. Off = the classic floating-pill shell. frameMusic swells the band
    // inward with the bass on frameMusicEdges ("sides" | "horizontal" | "all").
    property bool shellFrame: false
    property int frameThickness: 8
    property int frameRadius: 22
    property bool frameMusic: true
    property string frameMusicEdges: "sides"
    property int frameMusicStrength: 160
    // Frame colour: "surface" (the bar's own) | "accent" | "dynamic" (album
    // art while music plays, else the wallpaper theme) | "wallpaper" (sampled
    // from the wallpaper image itself) | "custom". frameTint
    // is how much of that colour is mixed into the bar background (%), so
    // text on the pills stays readable. The border is an outer stroke round
    // the band and pills: "subtle" | "accent" | "dynamic" (a gradient that
    // flows round the screen) | "custom".
    property string frameColor: "surface"
    property string frameCustomColor: "#7c5cff"
    property int frameTint: 35
    // The frame's (and its pills') own opacity, %, separate from uiOpacity.
    property int frameOpacity: 75
    property bool frameBorder: false
    property string frameBorderColor: "dynamic"
    property string frameBorderCustom: "#ffffff"
    property int frameBorderWidth: 2

    property string dateFormat: "%H:%M"
    readonly property var dateFormats: ["%H:%M", "%I:%M %p"]
    property real uiOpacity: 0.618
    property int uiScale: 10
    property int uiFontSize: 12

    // Island / shell motion (persisted, surfaced in Settings > Animations).
    // animScale multiplies every Theme.anim duration (1.0 = normal,
    // lower = faster); islandAnimStyle picks the IslandExpandClip easing.
    property bool animationsEnabled: true
    property real animScale: 1.0
    property string islandAnimStyle: "Emphasized"

    property real leftPanelHotZoneSize: 5
    property real rightPanelHotZoneSize: 5
    property bool leftPanelHotZone: true
    property bool rightPanelHotZone: true
    property bool notifDnd: false
    property bool leftPanelLock: false
    property bool rightPanelLock: false
    property int leftPanelWidth: 400
    property int rightPanelWidth: 250
    // Lockscreen grace period in seconds (Esc dismisses the lock without a
    // password within this window after locking), persisted, default 10.
    property int lockGraceSeconds: 10
    // Selected left-panel tab (persisted)
    property string leftPanelWidget: "About"
    // Weather city override (empty = Auto/IP), persisted
    property string weatherCity: ""

    // Right panel widgets — datalist with enabled flag.
    // CODE IS SOURCE OF TRUTH FOR ICONS: persist()/reload() only save/restore
    // {name, enabled} + order. Edit icons here (defaultRightPanelWidgets) and
    // they will not be clobbered by settings.json.
    property var rightPanelWidgets: root.defaultRightPanelWidgets()
    // Canonical widget definitions (names + code-owned icons + default enabled).
    function defaultRightPanelWidgets() {
        return [
            {
                name: "Media",
                icon: "\uf04b",
                enabled: true
            },
            {
                name: "NotificationHistory",
                icon: "\uf0f3",
                enabled: true
            },
            {
                name: "Calendar",
                icon: "\uf073",
                enabled: true
            },
            {
                name: "SystemResources",
                icon: "\uf4bc",
                enabled: true
            },
        ];
    }
    // Merge a saved widgets list onto the code defaults: keep file order +
    // enabled flags, drop unknown names, always take icons from code, append
    // any code-defined widgets missing from the file (new widgets).
    function mergeRightPanelWidgets(saved) {
        const defs = root.defaultRightPanelWidgets();
        const byName = {};
        for (const d of defs)
            byName[d.name] = d;
        if (!Array.isArray(saved))
            return defs;
        const out = [];
        for (const w of saved) {
            if (!w || !w.name || !byName[w.name])
                continue;
            if (out.some(e => e.name === w.name))
                continue;
            out.push({
                name: w.name,
                icon: byName[w.name].icon,
                enabled: (w.enabled ?? byName[w.name].enabled ?? true)
            });
        }
        for (const d of defs) {
            if (!out.some(e => e.name === d.name))
                out.push({
                    name: d.name,
                    icon: d.icon,
                    enabled: d.enabled
                });
        }
        return out.length > 0 ? out : defs;
    }
    property bool autoWorkspaceSwitching: true
    property bool gameModeEnabled: false

    // Bar-pinned crypto favorite (Information center)
    property var cryptoFavorite: ({
            symbol: "",
            timeframe: ""
        })

    // Single place listing the code-owned default sets: a new defaulted key
    // adds its row here (plus a default*/merge* pair only if the file shape
    // needs normalization on load). Startup snapshot; merge*() above keep
    // calling default*() so every load gets a fresh mutable copy.
    // (Stepping stone toward table-driven persist()/reload(): those bodies
    // stay authoritative until a live SUPER+B round-trip rewire verifies
    // byte-identical settings.json — not possible in a headless pass.)
    readonly property var _defaults: ({
            "rightPanelWidgets": defaultRightPanelWidgets()
        })
    // Static hyprland leaf metadata, transcribed verbatim from persist()
    // below ({name, min, max, type} per leaf + reload() default in def).
    // Table order matches persist()'s insertion order. NOTE the two
    // on-disk key orders persist() uses: general/decoration leaves are
    // {name, value, min, max, type} but blur/shadow leaves are
    // {name, value, type, min, max} (flagged typeFirst) — the loop below
    // reproduces both so on-disk bytes never change.
    readonly property var _hyprlandLeafSchema: [
        {
            path: ["general", "border_size"],
            name: "Border Size",
            min: 0,
            max: 10,
            type: "int",
            def: 0
        },
        {
            path: ["general", "gaps_in"],
            name: "Gaps In",
            min: 0,
            max: 20,
            type: "int",
            def: 7
        },
        {
            path: ["general", "gaps_out"],
            name: "Gaps Out",
            min: 0,
            max: 40,
            type: "int",
            def: 10
        },
        {
            path: ["decoration", "rounding"],
            name: "Rounding",
            min: 0,
            max: 50,
            type: "int",
            def: 16
        },
        {
            path: ["decoration", "active_opacity"],
            name: "Active Opacity",
            min: 0,
            max: 1,
            type: "float",
            def: 0.9
        },
        {
            path: ["decoration", "inactive_opacity"],
            name: "Inactive Opacity",
            min: 0,
            max: 1,
            type: "float",
            def: 0.8
        },
        {
            path: ["decoration", "blur", "enabled"],
            name: "Blur Enabled",
            min: 0,
            max: 1,
            type: "bool",
            def: true,
            typeFirst: true
        },
        {
            path: ["decoration", "blur", "size"],
            name: "Blur Size",
            min: 0,
            max: 10,
            type: "int",
            def: 4,
            typeFirst: true
        },
        {
            path: ["decoration", "blur", "passes"],
            name: "Blur Passes",
            min: 0,
            max: 10,
            type: "int",
            def: 4,
            typeFirst: true
        },
        {
            path: ["decoration", "blur", "xray"],
            name: "Blur Xray",
            min: 0,
            max: 1,
            type: "bool",
            def: false,
            typeFirst: true
        },
        {
            path: ["decoration", "shadow", "enabled"],
            name: "Shadow Enabled",
            min: 0,
            max: 1,
            type: "bool",
            def: true,
            typeFirst: true
        },
        {
            path: ["decoration", "shadow", "range"],
            name: "Shadow Range",
            min: 0,
            max: 20,
            type: "int",
            def: 15,
            typeFirst: true
        },
        {
            path: ["decoration", "shadow", "render_power"],
            name: "Shadow Render Power",
            min: 0,
            max: 20,
            type: "int",
            def: 3,
            typeFirst: true
        }
    ]

    // ChatBot model (Claude Code alias; default: first provider).
    property string chatBotApi: "opus"

    // Blur settings (size / passes / enabled)
    property bool barBlur: true
    property int barBlurPasses: 3
    property int barBlurSize: 4

    // File manager (detected + selected)
    property var fileManagerOptions: []
    property string fileManager: ""

    // Hyprland settings (plain values internally; persist() writes the
    // {name,value,min,max,type} leaf shape the settings panel renders).
    property var hyprland: ({
            general: {
                border_size: 0,
                gaps_in: 7,
                gaps_out: 10
            },
            decoration: {
                rounding: 16,
                active_opacity: 0.9,
                inactive_opacity: 0.8,
                blur: {
                    enabled: true,
                    size: 4,
                    passes: 4,
                    xray: false
                },
                shadow: {
                    enabled: true,
                    range: 15,
                    render_power: 3
                }
            }
        })

    // --- functions ---

    function fmt(d, f) {
        const p = n => n.toString().padStart(2, "0");
        if (f === "%I:%M %p") {
            let h = d.getHours() % 12;
            if (h === 0)
                h = 12;
            return `${p(h)}:${p(d.getMinutes())} ${d.getHours() < 12 ? "AM" : "PM"}`;
        }
        return `${p(d.getHours())}:${p(d.getMinutes())}`;
    }

    // Update a setting by dotted path and persist to settings.json
    function updateSetting(path, value) {
        // Dotted paths that map to flat QS properties (Singleton cannot
        // gain new properties at runtime, so root["rightPanel"] = {} throws).
        const aliases = {
            "bar.lock": "barLock",
            "bar.smartHide": "barSmartHide",
            "bar.expanded": "barDefault",
            "bar.default": "barDefault",
            "bar.fullWidth": "barFullWidth",
            "bar.revealPressure": "revealInPressure",
            "bar.revealInPressure": "revealInPressure",
            "bar.revealOutPressure": "revealOutPressure",
            "bar.orientation": "barOrientation",
            "mpris.visualizer": "mprisVisualizer",
            "visualizer.style": "visualizerStyle",
            "frame.enable": "shellFrame",
            "frame.thickness": "frameThickness",
            "frame.radius": "frameRadius",
            "frame.music": "frameMusic",
            "frame.musicEdges": "frameMusicEdges",
            "frame.musicStrength": "frameMusicStrength",
            "frame.color": "frameColor",
            "frame.customColor": "frameCustomColor",
            "frame.tint": "frameTint",
            "frame.opacity": "frameOpacity",
            "frame.border": "frameBorder",
            "frame.borderColor": "frameBorderColor",
            "frame.borderCustom": "frameBorderCustom",
            "frame.borderWidth": "frameBorderWidth",
            "bar.blur": "barBlur",
            "bar.blurSize": "barBlurSize",
            "bar.blurPasses": "barBlurPasses",
            "ui.opacity": "uiOpacity",
            "ui.scale": "uiScale",
            "ui.fontSize": "uiFontSize",
            "animations.enabled": "animationsEnabled",
            "animations.scale": "animScale",
            "animations.islandStyle": "islandAnimStyle",
            "leftPanel.hotZoneSize": "leftPanelHotZoneSize",
            "rightPanel.hotZoneSize": "rightPanelHotZoneSize",
            "leftPanel.hotZone": "leftPanelHotZone",
            "rightPanel.hotZone": "rightPanelHotZone",
            "leftPanel.lock": "leftPanelLock",
            "rightPanel.lock": "rightPanelLock",
            "leftPanel.width": "leftPanelWidth",
            "leftPanel.widget": "leftPanelWidget",
            "weather.city": "weatherCity",
            "rightPanel.width": "rightPanelWidth",
            "rightPanel.widgets": "rightPanelWidgets",
            "crypto.favorite": "cryptoFavorite",
            "notifications.dnd": "notifDnd",
            "lockscreen.graceSeconds": "lockGraceSeconds",
            "autoWorkspaceSwitching": "autoWorkspaceSwitching",
            "gameMode.enabled": "gameModeEnabled",
            "fileManager": "fileManager",
            "chatBot.api": "chatBotApi"
        };
        if (aliases[path] !== undefined) {
            // Widget icons are code-owned: never store incoming icons, merge
            // onto the code defaults so a stale settings.json can't stick.
            if (path === "rightPanel.widgets") {
                root[aliases[path]] = root.mergeRightPanelWidgets(value);
            } else {
                root[aliases[path]] = value;
            }
            persist();
            return;
        }
        const parts = path.split(".");
        let obj = root;
        for (let i = 0; i < parts.length - 1; i++) {
            const p = parts[i];
            if (obj[p] === undefined || typeof obj[p] !== "object" || obj[p] === null) {
                return;
            } else {
                obj = obj[p];
            }
        }
        const key = parts[parts.length - 1];
        obj[key] = value;
        // Reassign a FRESH clone so the top-level var change signal fires.
        // (Assigning the same object reference back is a no-op: nested
        // bindings like `Settings.hyprland.general` never re-evaluate.)
        if (parts.length > 1) {
            root[parts[0]] = Object.assign({}, obj);
        }
        persist();
    }

    // Persist current settings back to the JSON file.
    // Shape is nested (bar.lock, leftPanel.width, ...) — reload() reads the
    // same shape and tolerates unknown/missing keys.
    // Leaf settings are written as {value}; plain-value settings (locks,
    // plain-value settings (locks, widths, dnd, fileManager) stay plain.
    function persist() {
        if (!root.ready)
            return;
        try {
            const s = {
                bar: {
                    lock: {
                        value: root.barLock
                    },
                    smartHide: {
                        value: root.barSmartHide
                    },
                    default: {
                        value: root.barDefault
                    },
                    expanded: {
                        value: root.barDefault
                    },
                    fullWidth: {
                        value: root.barFullWidth
                    },
                    revealInPressure: {
                        value: root.revealInPressure
                    },
                    revealOutPressure: {
                        value: root.revealOutPressure
                    },
                    orientation: {
                        value: root.barOrientation
                    },
                    blur: {
                        value: root.barBlur
                    },
                    blurSize: {
                        value: root.barBlurSize
                    },
                    blurPasses: {
                        value: root.barBlurPasses
                    }
                },
                mpris: {
                    visualizer: {
                        value: root.mprisVisualizer
                    }
                },
                visualizer: {
                    style: {
                        value: root.visualizerStyle
                    }
                },
                frame: {
                    enable: { value: root.shellFrame },
                    thickness: { value: root.frameThickness },
                    radius: { value: root.frameRadius },
                    music: { value: root.frameMusic },
                    musicEdges: { value: root.frameMusicEdges },
                    musicStrength: { value: root.frameMusicStrength },
                    color: { value: root.frameColor },
                    customColor: { value: root.frameCustomColor },
                    tint: { value: root.frameTint },
                    opacity: { value: root.frameOpacity },
                    border: { value: root.frameBorder },
                    borderColor: { value: root.frameBorderColor },
                    borderCustom: { value: root.frameBorderCustom },
                    borderWidth: { value: root.frameBorderWidth }
                },
                dateFormat: root.dateFormat,
                crypto: {
                    favorite: root.cryptoFavorite
                },
                ui: {
                    opacity: {
                        value: root.uiOpacity
                    },
                    scale: {
                        value: root.uiScale
                    },
                    fontSize: {
                        value: root.uiFontSize
                    }
                },
                animations: {
                    enabled: {
                        value: root.animationsEnabled
                    },
                    scale: {
                        value: root.animScale
                    },
                    islandStyle: root.islandAnimStyle
                },
                leftPanel: {
                    hotZoneSize: {
                        value: root.leftPanelHotZoneSize
                    },
                    hotZone: {
                        value: root.leftPanelHotZone
                    },
                    lock: root.leftPanelLock,
                    width: root.leftPanelWidth,
                    widget: {
                        name: root.leftPanelWidget
                    }
                },
                rightPanel: {
                    hotZoneSize: {
                        value: root.rightPanelHotZoneSize
                    },
                    hotZone: {
                        value: root.rightPanelHotZone
                    },
                    lock: root.rightPanelLock,
                    width: root.rightPanelWidth,
                    // Icons are code-owned: persist only {name, enabled} +
                    // order so icon edits in code are never clobbered.
                    widgets: (root.rightPanelWidgets || []).map(w => ({
                                name: w.name,
                                enabled: !!w.enabled
                            }))
                },
                notifications: {
                    dnd: root.notifDnd
                },
                lockscreen: {
                    graceSeconds: root.lockGraceSeconds
                },
                weather: {
                    city: root.weatherCity
                },
                autoWorkspaceSwitching: {
                    value: root.autoWorkspaceSwitching
                },
                gameMode: {
                    enabled: {
                        value: root.gameModeEnabled
                    }
                },
                // Hyprland leaf shape {name,value,min,max,type} — the settings
                // panel renders from it (plain numbers would be mistaken for
                // nested groups and render nothing). Driven by
                // _hyprlandLeafSchema above (single source for labels/limits);
                // blur/shadow leaves keep their {name,value,type,min,max}
                // order via typeFirst so on-disk bytes never change.
                "hyprland": (() => {
                        const out = {};
                        for (const leaf of root._hyprlandLeafSchema) {
                            const v = leaf.path.reduce((o, k) => ((o == null) ? o : o[k]), root.hyprland) ?? leaf.def;
                            let node = out;
                            for (let i = 0; i < leaf.path.length - 1; i++) {
                                const g = leaf.path[i];
                                if (node[g] === undefined)
                                    node[g] = {};
                                node = node[g];
                            }
                            const key = leaf.path[leaf.path.length - 1];
                            node[key] = (leaf.typeFirst === true) ? {
                                name: leaf.name,
                                value: v,
                                type: leaf.type,
                                min: leaf.min,
                                max: leaf.max
                            } : {
                                name: leaf.name,
                                value: v,
                                min: leaf.min,
                                max: leaf.max,
                                type: leaf.type
                            };
                        }
                        return out;
                    })(),
                fileManager: root.fileManager,
                "chatBot": {
                    api: root.chatBotApi
                }
            };
            _lastText = JSON.stringify(s, null, 2);
            _file.setText(_lastText);
        } catch (e) {
            console.warn("[Settings] Failed to persist:", e);
        }
    }

    // FileView for settings. NOTE: bare reload() here would resolve to
    // FileView.reload() (re-read method), NOT the settings parser below —
    // always qualify with root. (This shadowing was why settings silently
    // stopped applying after a restart.)
    property FileView _file: FileView {
        path: `${Quickshell.env("HOME")}/.cache/quickshell/settings/settings.json`
        watchChanges: true
        // Delayed: FileView saves are async, so an immediate re-read can
        // catch pre-write bytes and persist the stale state back over the
        // fresh one (seen: limit 30 reverted to 40 in-file). 300ms lets our
        // own write land; _lastText then makes it a no-op.
        onFileChanged: _reloadTimer.restart()
        onLoaded: {
            root.reload();
            root.ready = true;
        }
    }
    // Last text we wrote (or successfully adopted): reload() skips it so
    // our own watcher echo can't churn assignments back over newer state.
    property string _lastText: ""
    property Timer _reloadTimer: Timer {
        interval: 300
        onTriggered: root.reload()
    }
    // Fallback: FileView never emits loaded for a missing file, which left
    // ready=false forever and gated every persist() (no settings.json was
    // ever created). If onLoaded hasn't fired in 2s, adopt disk state and
    // open the gate — persist() then creates the file with current values.
    property Timer _readyTimer: Timer {
        interval: 2000
        repeat: false
        onTriggered: {
            if (root.ready)
                return;
            root.reload();
            root.ready = true;
            root.persist();
        }
    }
    // Gate: FileView loads async, so any persist() before the first load
    // would write in-memory defaults over the user's saved file (seen:
    // saved values clobbered back to defaults on restart). Nothing persists
    // until the on-disk values have been adopted.
    property bool ready: false

    // Fresh on-disk settings for upload sync — never an empty stub
    // (uploading {} would wipe remote).
    function readLocalSettingsJson() {
        try {
            const text = _file.text();
            if (text && text.trim().startsWith("{"))
                return JSON.parse(text);
        } catch (e) {}
        return {};
    }

    function reload() {
        try {
            const text = _file.text();
            if (text !== "" && text.trim().startsWith("{")) {
                if (text === root._lastText)
                    return;
                const s = JSON.parse(text);
                root._lastText = text;
                root.barLock = s.bar?.lock?.value ?? true;
                root.barSmartHide = s.bar?.smartHide?.value ?? false;
                root.barDefault = s.bar?.default?.value ?? s.bar?.expanded?.value ?? true;
                root.barFullWidth = s.bar?.fullWidth?.value ?? false;
                root.revealInPressure = s.bar?.revealInPressure?.value ?? s.bar?.revealPressure?.value ?? 250;
                root.revealOutPressure = s.bar?.revealOutPressure?.value ?? s.bar?.revealPressure?.value ?? 1000;
                root.barOrientation = s.bar?.orientation?.value ?? true;
                root.mprisVisualizer = s.mpris?.visualizer?.value ?? false;

                // iNiR visualizer import: validate the enum so a stale or
                // corrupt settings.json can't wedge the shell
                // (islandAnimStyle precedent).
                const _vs = s.visualizer?.style?.value;
                root.visualizerStyle = ["bars", "wave", "off"].includes(_vs) ? _vs : "bars";

                // Shell frame: clamp numbers, validate the edge enum.
                const _clampN = (v, lo, hi, d) => Number.isFinite(Number(v)) ? Math.max(lo, Math.min(hi, Math.round(Number(v)))) : d;
                root.shellFrame = s.frame?.enable?.value ?? false;
                root.frameThickness = _clampN(s.frame?.thickness?.value, 2, 24, 8);
                root.frameRadius = _clampN(s.frame?.radius?.value, 0, 48, 22);
                root.frameMusic = s.frame?.music?.value ?? true;
                const _fe = s.frame?.musicEdges?.value;
                root.frameMusicEdges = ["sides", "horizontal", "all"].includes(_fe) ? _fe : "sides";
                root.frameMusicStrength = _clampN(s.frame?.musicStrength?.value, 50, 300, 160);
                const _hex = (v, d) => /^#[0-9a-fA-F]{6}$/.test(String(v ?? "")) ? String(v) : d;
                const _fc = s.frame?.color?.value;
                root.frameColor = ["surface", "accent", "dynamic", "wallpaper", "custom"].includes(_fc) ? _fc : "surface";
                root.frameCustomColor = _hex(s.frame?.customColor?.value, "#7c5cff");
                root.frameTint = _clampN(s.frame?.tint?.value, 0, 100, 35);
                root.frameOpacity = _clampN(s.frame?.opacity?.value, 10, 100, 75);
                root.frameBorder = s.frame?.border?.value ?? false;
                const _bc = s.frame?.borderColor?.value;
                root.frameBorderColor = ["subtle", "accent", "dynamic", "wallpaper", "custom"].includes(_bc) ? _bc : "dynamic";
                root.frameBorderCustom = _hex(s.frame?.borderCustom?.value, "#ffffff");
                root.frameBorderWidth = _clampN(s.frame?.borderWidth?.value, 1, 6, 2);

                root.dateFormat = s.dateFormat ?? "%H:%M";
                root.cryptoFavorite = s.crypto?.favorite ?? {
                    symbol: "",
                    timeframe: ""
                };
                root.uiOpacity = s.ui?.opacity?.value ?? 0.618;
                root.uiScale = s.ui?.scale?.value ?? 10;
                root.uiFontSize = s.ui?.fontSize?.value ?? 12;

                // Shell motion: accept both {value} leaves and plain values;
                // clamp scale so a stale file can't freeze or stall motion.
                const _ae = s.animations?.enabled;
                root.animationsEnabled = ((typeof _ae === "object" && _ae !== null ? _ae.value : _ae) ?? true);
                const _as = s.animations?.scale;
                const _asV = ((typeof _as === "object" && _as !== null ? _as.value : _as) ?? 1.0);
                root.animScale = Math.min(2.0, Math.max(0.2, Number(_asV) || 1.0));
                const _ais = s.animations?.islandStyle;
                const _aisV = ((typeof _ais === "object" && _ais !== null ? _ais.value : _ais) ?? "Emphasized");
                const _styles = ["Standard", "Emphasized", "ExpressiveFast", "ExpressiveDefault", "ExpressiveSlow"];
                root.islandAnimStyle = _styles.includes(_aisV) ? _aisV : "Emphasized";

                root.leftPanelHotZoneSize = s.leftPanel?.hotZoneSize?.value ?? 5;
                root.rightPanelHotZoneSize = s.rightPanel?.hotZoneSize?.value ?? 5;
                root.leftPanelHotZone = s.leftPanel?.hotZone?.value ?? true;
                root.rightPanelHotZone = s.rightPanel?.hotZone?.value ?? true;
                root.notifDnd = s.notifications?.dnd ?? false;
                root.leftPanelLock = !!s.leftPanel?.lock;
                root.rightPanelLock = !!s.rightPanel?.lock;
                root.leftPanelWidth = (typeof s.leftPanel?.width === "object" && s.leftPanel?.width !== null ? s.leftPanel.width.value : s.leftPanel?.width) ?? 400;
                // The file may store the selector object {name, icon}; QS persists
                // only {name} and restores only the name — left icons live in
                // (LeftIsland) and are never clobbered by the file.
                // legacy QS files used the flat "leftPanel.widget" key.
                const _lpw = s["leftPanel.widget"] ?? s.leftPanel?.widget;
                const _lpwName = (typeof _lpw === "string" ? _lpw : _lpw?.name) ?? "About";
                // Tabs that were removed (UserProfile, Donations, ...) open About.
                root.leftPanelWidget = ["About", "ChatBot", "SettingsWidget", "CustomScripts", "KeyBinds"].includes(_lpwName) ? _lpwName : "About";
                const _wth = s.weather?.city ?? s.weatherCity;
                root.weatherCity = ((typeof _wth === "object" && _wth !== null ? _wth.value : _wth) ?? "");
                root.rightPanelWidth = (typeof s.rightPanel?.width === "object" && s.rightPanel?.width !== null ? s.rightPanel.width.value : s.rightPanel?.width) ?? 250;
                // Drop stale/removed widgets (e.g. retired Crypto/ScriptTimer)
                // so deleted options never reappear from an old settings file.
                // Icons are code-owned: file contributes only order + enabled.
                if (Array.isArray(s.rightPanel?.widgets)) {
                    root.rightPanelWidgets = root.mergeRightPanelWidgets(s.rightPanel.widgets);
                }
                root.autoWorkspaceSwitching = s.autoWorkspaceSwitching?.value ?? true;
                const _gm = s.gameMode?.enabled;
                root.gameModeEnabled = (typeof _gm === "object" && _gm !== null) ? (_gm.value ?? false) : (_gm ?? false);

                // ChatBot provider (restored on launch; stored as the model
                // value string here).
                const cbApi = s.chatBot?.api;
                root.chatBotApi = (cbApi && typeof cbApi === "object" ? cbApi.value : cbApi) ?? "opus";

                // Blur settings
                root.barBlur = s.bar?.blur?.value ?? true;
                root.barBlurPasses = s.bar?.blurPasses?.value ?? 3;
                root.barBlurSize = s.bar?.blurSize?.value ?? 4;

                // Lockscreen grace period (seconds of free Esc dismiss)
                root.lockGraceSeconds = s.lockscreen?.graceSeconds ?? 10;

                // File manager
                root.fileManager = s.fileManager ?? "";

                // Hyprland settings (full schema incl. blur passes 4, xray,
                // xray, gaps, opacities — previously partial, which reset
                // missing keys to 0/false on every reload). Defaults come
                // from _hyprlandLeafSchema so persist()/reload() agree.
                root.hyprland = (() => {
                        const out = {};
                        for (const leaf of root._hyprlandLeafSchema) {
                            const node = leaf.path.reduce((o, k) => ((o == null) ? undefined : o[k]), s.hyprland);
                            const v = ((typeof node === "object" && node !== null) ? node.value : undefined) ?? leaf.def;
                            let target = out;
                            for (let i = 0; i < leaf.path.length - 1; i++) {
                                const g = leaf.path[i];
                                if (target[g] === undefined)
                                    target[g] = {};
                                target = target[g];
                            }
                            target[leaf.path[leaf.path.length - 1]] = v;
                        }
                        return out;
                    })();
            }
        } catch (e) {
            console.warn("[Settings] parse failed:", e);
        }
    }

    Component.onCompleted: {
        root.reload();
        root._readyTimer.start();
        Qt.callLater(function () {
            if (root.gameModeEnabled)
                root.applyGameMode(true);
        });
    }

    function applyGameMode(enabled) {
        const stateFile = "${XDG_RUNTIME_DIR:-/tmp}/archeclipse-gamemode-profile-$UID";
        const requestPidFile = "${XDG_RUNTIME_DIR:-/tmp}/archeclipse-gamemode-request-$UID";
        root.gameModeEnabled = enabled;
        Quickshell.execDetached(["bash", "-c", enabled ? `set -u
            hyprctl eval 'hl.config({
                general = {
                    gaps_in = 0,
                    gaps_out = 0,
                    border_size = 1,
                    allow_tearing = true,
                },
                animations = {
                    enabled = false,
                },
                decoration = {
                    shadow = { enabled = false },
                    blur = { enabled = false },
                    rounding = 0,
                },
            })' >/dev/null 2>&1 || true
            if command -v powerprofilesctl >/dev/null 2>&1; then
                profile="$(powerprofilesctl get 2>/dev/null || true)"
                [ -n "$profile" ] && printf '%s\n' "$profile" > "${stateFile}"
                if powerprofilesctl list 2>/dev/null | grep -qE '(^|[[:space:]])performance([[:space:]]|:)'; then
                    powerprofilesctl set performance >/dev/null 2>&1 || true
                fi
            fi
            if command -v gamemoded >/dev/null 2>&1; then
                if [ ! -s "${requestPidFile}" ] || ! kill -0 "$(cat "${requestPidFile}")" 2>/dev/null; then
                    gamemoded --request >/dev/null 2>&1 &
                    printf '%s\n' "$!" > "${requestPidFile}"
                fi
            fi` : `set -u
            hyprctl reload >/dev/null 2>&1 || true
            if [ -s "${requestPidFile}" ]; then
                request_pid="$(cat "${requestPidFile}")"
                if kill -0 "$request_pid" 2>/dev/null; then
                    kill "$request_pid" 2>/dev/null || true
                    for _ in 1 2 3 4 5; do
                        kill -0 "$request_pid" 2>/dev/null || break
                        sleep 0.1
                    done
                fi
                rm -f "${requestPidFile}"
            fi
            if command -v powerprofilesctl >/dev/null 2>&1 && [ -s "${stateFile}" ]; then
                profile="$(tr -d '\r\n' < "${stateFile}")"
                if [ -n "$profile" ]; then
                    for _ in 1 2 3; do
                        powerprofilesctl set "$profile" >/dev/null 2>&1 || true
                        [ "$(powerprofilesctl get 2>/dev/null || true)" = "$profile" ] && break
                        sleep 0.2
                    done
                fi
                rm -f "${stateFile}"
            fi`]);
        root.schedulePersist();
    }

    // Auto-persist: debounce writes so the settings file isn't thrashed
    // by rapid UI toggles (e.g. dragging the opacity slider).
    property Timer _persistTimer: Timer {
        interval: 250
        onTriggered: persist()
    }
    function schedulePersist() {
        if (root.ready)
            _persistTimer.start();
    }

    // Watch directly-written settings properties and auto-persist.
    // Rule: a handler exists ONLY for keys with a direct `Settings.x = ...`
    // writer outside updateSetting() (verified via
    // `rg "Settings\.[a-zA-Z]+ =" widgets/ services/ theme/ shell.qml` plus
    // bracket writes). updateSetting() persists directly, so its exclusive
    // keys need no handler.
    Connections {
        target: root
        function onBarLockChanged() {
            root.schedulePersist();
        }
        function onBarSmartHideChanged() {
            root.schedulePersist();
        }
        function onBarDefaultChanged() {
            root.schedulePersist();
        }
        function onBarFullWidthChanged() {
            root.schedulePersist();
        }
        function onRevealInPressureChanged() {
            root.schedulePersist();
        }
        function onRevealOutPressureChanged() {
            root.schedulePersist();
        }
        function onBarOrientationChanged() {
            root.schedulePersist();
        }
        function onRightPanelWidgetsChanged() {
            root.schedulePersist();
        }
        function onCryptoFavoriteChanged() {
            root.schedulePersist();
        }
        function onDateFormatChanged() {
            root.schedulePersist();
        }
        function onUiOpacityChanged() {
            root.schedulePersist();
        }
        function onUiScaleChanged() {
            root.schedulePersist();
        }
        function onUiFontSizeChanged() {
            root.schedulePersist();
        }
        function onAnimationsEnabledChanged() {
            root.schedulePersist();
        }
        function onAnimScaleChanged() {
            root.schedulePersist();
        }
        function onIslandAnimStyleChanged() {
            root.schedulePersist();
        }
        function onVisualizerStyleChanged() {
            root.schedulePersist();
        }
        function onShellFrameChanged() { root.schedulePersist(); }
        function onFrameThicknessChanged() { root.schedulePersist(); }
        function onFrameRadiusChanged() { root.schedulePersist(); }
        function onFrameMusicChanged() { root.schedulePersist(); }
        function onFrameMusicEdgesChanged() { root.schedulePersist(); }
        function onFrameMusicStrengthChanged() { root.schedulePersist(); }
        function onFrameColorChanged() { root.schedulePersist(); }
        function onFrameCustomColorChanged() { root.schedulePersist(); }
        function onFrameTintChanged() { root.schedulePersist(); }
        function onFrameOpacityChanged() { root.schedulePersist(); }
        function onFrameBorderChanged() { root.schedulePersist(); }
        function onFrameBorderColorChanged() { root.schedulePersist(); }
        function onFrameBorderCustomChanged() { root.schedulePersist(); }
        function onFrameBorderWidthChanged() { root.schedulePersist(); }
        function onLeftPanelHotZoneSizeChanged() {
            root.schedulePersist();
        }
        function onRightPanelHotZoneSizeChanged() {
            root.schedulePersist();
        }
        function onLeftPanelHotZoneChanged() {
            root.schedulePersist();
        }
        function onRightPanelHotZoneChanged() {
            root.schedulePersist();
        }
        function onLockGraceSecondsChanged() {
            root.schedulePersist();
        }
        function onLeftPanelLockChanged() {
            root.schedulePersist();
        }
        function onRightPanelLockChanged() {
            root.schedulePersist();
        }
        function onLeftPanelWidthChanged() {
            root.schedulePersist();
        }
        function onLeftPanelWidgetChanged() {
            root.schedulePersist();
        }
        function onRightPanelWidthChanged() {
            root.schedulePersist();
        }
        function onHyprlandChanged() {
            root.schedulePersist();
        }
        function onBarBlurChanged() {
            root.schedulePersist();
        }
        function onBarBlurPassesChanged() {
            root.schedulePersist();
        }
        function onBarBlurSizeChanged() {
            root.schedulePersist();
        }
        function onGameModeEnabledChanged() {
            root.schedulePersist();
        }
        function onChatBotApiChanged() {
            root.schedulePersist();
        }
        function onFileManagerChanged() {
            root.schedulePersist();
        }
    }
}
