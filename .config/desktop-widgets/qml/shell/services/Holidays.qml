pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Public holidays for the calendar widget. ArchEclipse has no Ryoku daemon,
// so they come straight from Nager.Date (date.nager.at, free, no key) for the
// calendar's region (an ISO country code such as "ES" or "US"), one request
// per visible year, cached on disk for a week so the calendar works offline
// and the API is barely touched. Empty region = no holidays (and no traffic).
Singleton {
    id: root

    property var frame: ({ status: "idle", region: "", source: "date.nager.at", days: [] })
    readonly property string status: frame.status || "idle"
    readonly property string region: frame.region || ""
    readonly property string errorText: frame.error || ""
    readonly property var days: Array.isArray(frame.days) ? frame.days : []
    property var byDate: ({})
    property string requestedRegion: ""
    property var requestedYears: []

    readonly property string cacheDir: (Quickshell.env("XDG_CACHE_HOME") || (Quickshell.env("HOME") + "/.cache")) + "/desktop-widgets/holidays"

    function forDate(key) { return root.byDate[key] || []; }
    function hasDate(key) { return root.forDate(key).length > 0; }

    function configure(region, years) {
        // Blank = the locale's country (en_US -> US); "US-CA" = the US list
        // plus California's regional days.
        let r = String(region || "").trim().toUpperCase();
        if (r === "") {
            const loc = (Quickshell.env("LC_TIME") || Quickshell.env("LANG") || Qt.locale().name || "").split(".")[0];
            r = loc.indexOf("_") > 0 ? loc.split("_")[1].toUpperCase() : "";
        }
        const ys = (years || []).slice().sort();
        if (root.requestedRegion === r && root.requestedYears.join(",") === ys.join(","))
            return;
        root.requestedRegion = r;
        root.requestedYears = ys;
        if (r === "" || ys.length === 0) {
            root.apply({ status: "idle", region: "", days: [] });
            return;
        }
        root.apply({ status: "loading", region: r, days: root.days });
        // One shell run: per year, use the cache when fresh (< 7 days), else
        // fetch it; print every year's list as one JSON array per line.
        const script = 'd="$1"; r="$2"; shift 2; mkdir -p "$d"; for y in "$@"; do f="$d/$r-$y.json"; '
            + 'if [ ! -s "$f" ] || [ -n "$(find "$f" -mtime +7 2>/dev/null)" ]; then '
            + 'curl -fsSL --max-time 12 "https://date.nager.at/api/v3/PublicHolidays/$y/$r" -o "$f.tmp" && mv "$f.tmp" "$f"; fi; '
            + '[ -s "$f" ] && tr -d "\\n" < "$f" && echo; done';
        fetch.command = ["bash", "-c", script, "holidays", root.cacheDir, r.split("-")[0]].concat(ys.map(String));
        fetch.running = true;
    }

    function apply(next) {
        const index = {};
        for (const h of next.days || []) {
            if (!h || typeof h.date !== "string")
                continue;
            (index[h.date] = index[h.date] || []).push(h);
        }
        root.frame = next;
        root.byDate = index;
    }

    Process {
        id: fetch
        stdout: StdioCollector {
            onStreamFinished: {
                const days = [];
                for (const line of text.split("\n")) {
                    if (line.trim() === "")
                        continue;
                    try {
                        const sub = root.requestedRegion.indexOf("-") > 0 ? root.requestedRegion : "";
                        for (const h of JSON.parse(line)) {
                            if (h.global === false && !(sub !== "" && (h.counties || []).indexOf(sub) !== -1))
                                continue;
                            days.push({ date: h.date, name: h.localName && h.localName !== h.name ? h.name + " (" + h.localName + ")" : h.name, global: h.global !== false });
                        }
                    } catch (e) {
                    }
                }
                root.apply({ status: days.length > 0 ? "ready" : "error", region: root.requestedRegion,
                    source: "date.nager.at", days: days, error: days.length > 0 ? "" : "No holidays found for " + root.requestedRegion });
            }
        }
    }
}
