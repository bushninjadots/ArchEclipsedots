pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

// Screen time (after Serpantinum's Digital Wellbeing): seconds per app per
// day, counted while a window has focus and you are not idle (2 min without
// input; video players that inhibit idle still count). Kept per day in
// ~/.local/share/archeclipse/screentime/YYYY-MM-DD.json, flushed each minute.
Singleton {
    id: root

    readonly property string dir: (Quickshell.env("XDG_DATA_HOME") || (Quickshell.env("HOME") + "/.local/share")) + "/archeclipse/screentime"
    property string day: root._today()
    // app class -> seconds, for `day`.
    property var today: ({})
    readonly property int total: {
        let t = 0;
        for (const k in root.today)
            t += root.today[k];
        return t;
    }
    // [{ app, secs }] most used first.
    readonly property var top: Object.keys(root.today).map(k => ({ app: k, secs: root.today[k] })).sort((a, b) => b.secs - a.secs)
    // Last 7 days' totals, oldest first: [{ day, secs }].
    property var week: []

    function _today() {
        const d = new Date();
        const p = v => String(v).padStart(2, "0");
        return d.getFullYear() + "-" + p(d.getMonth() + 1) + "-" + p(d.getDate());
    }
    function fmt(secs) {
        const m = Math.floor(secs / 60), h = Math.floor(m / 60);
        return h > 0 ? h + "h " + (m % 60) + "m" : m > 0 ? m + "m" : secs + "s";
    }
    // Friendlier names for common classes ("zen" -> "Zen").
    function label(app) {
        const e = DesktopEntries.heuristicLookup(app);
        return e?.name || (app.charAt(0).toUpperCase() + app.slice(1));
    }
    function icon(app) {
        return DesktopEntries.heuristicLookup(app)?.icon || app.toLowerCase();
    }

    IdleMonitor {
        id: idle
        timeout: 120
        respectInhibitors: true
    }

    property bool _dirty: false
    Timer {
        interval: 10000
        running: true
        repeat: true
        onTriggered: {
            const d = root._today();
            if (d !== root.day) {
                root.flush();
                root.day = d;
                root.today = ({});
                weekProc.running = true;
            }
            if (idle.isIdle)
                return;
            const w = Hyprland.activeToplevel;
            const app = w ? (w.wayland?.appId || w.lastIpcObject?.class || "") : "";
            if (app === "")
                return;
            const t = Object.assign({}, root.today);
            t[app] = (t[app] || 0) + 10;
            root.today = t;
            root._dirty = true;
        }
    }
    Timer {
        interval: 60000
        running: true
        repeat: true
        onTriggered: root.flush()
    }
    function flush() {
        if (!root._dirty)
            return;
        root._dirty = false;
        file.setText(JSON.stringify(root.today));
    }

    FileView {
        id: file
        path: root.dir + "/" + root.day + ".json"
        printErrors: false
        atomicWrites: true
        onLoaded: {
            try {
                // Merge in case a few ticks counted before the load landed.
                const disk = JSON.parse(text() || "{}");
                const t = Object.assign({}, disk);
                for (const k in root.today)
                    t[k] = Math.max(t[k] || 0, root.today[k]);
                root.today = t;
            } catch (e) {
            }
        }
    }
    Process {
        id: mk
        running: true
        command: ["mkdir", "-p", root.dir]
    }
    // Week totals from the day files (sums each file's values).
    Process {
        id: weekProc
        running: true
        command: ["bash", "-c", 'cd "$1" 2>/dev/null || exit 0; for i in 6 5 4 3 2 1 0; do d=$(date -d "-$i day" +%F); '
            + 's=0; [ -f "$d.json" ] && s=$(jq "[.[]] | add // 0" "$d.json" 2>/dev/null); echo "$d ${s:-0}"; done', "week", root.dir]
        stdout: StdioCollector {
            onStreamFinished: {
                root.week = text.trim().split("\n").filter(l => l !== "").map(l => {
                    const p = l.split(" ");
                    return { day: p[0], secs: Number(p[1]) || 0 };
                });
            }
        }
    }
    Component.onDestruction: root.flush()
}
