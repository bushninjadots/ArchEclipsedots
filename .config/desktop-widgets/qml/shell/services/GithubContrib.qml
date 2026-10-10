pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// GitHub contribution feed for the activity heatmap widget.
// Fetches from github-contributions-api and caches locally.
// The widget binds to `data` (and `total`) to render the heatmap.
//
// Usage in widget:
//   GithubContrib.data     ->  [{ date: "YYYY-MM-DD", count: n }, ...]
//   GithubContrib.total    ->  total contributions this year
//   GithubContrib.user     ->  current username
//   GithubContrib.loading  ->  true while fetching
//   GithubContrib.error    ->  error string or ""
//   GithubContrib.hasData  ->  true once a non-empty feed has loaded
//   GithubContrib.setUser(name) ->  persist the username and refetch

Singleton {
    id: root

    readonly property string fetcher: Quickshell.env("HOME") + "/.config/desktop-widgets/bin/github-contributions"
    readonly property string cacheDir: (Quickshell.env("XDG_CACHE_HOME") || (Quickshell.env("HOME") + "/.cache")) + "/desktop-widgets/github"

    // Public API
    readonly property var data: root.frame.contributions || []
    readonly property int total: root.frame.total || 0
    readonly property string user: root.frame.user || ""
    readonly property int year: root.frame.year || 0
    readonly property var years: root.frame.years || []
    readonly property bool loading: root.frame.status === "loading"
    readonly property string error: root.frame.error || ""
    readonly property bool hasData: root.frame.status === "loaded" && (root.frame.contributions || []).length > 0

    // The frame is reassigned wholesale on every update so bindings re-evaluate,
    // matching the other services (Music/Weather/Updates). Mutating a sub-property
    // of a `var` property would not emit a change signal.
    property var frame: ({
        status: "loading",
        contributions: [],
        total: 0,
        user: "",
        year: 0,
        years: [],
        error: "",
        lastUpdated: 0
    })

    function update(patch) {
        root.frame = {
            contributions: patch.contributions !== undefined ? patch.contributions : root.frame.contributions,
            total: patch.total !== undefined ? patch.total : root.frame.total,
            user: patch.user !== undefined ? patch.user : root.frame.user,
            year: patch.year !== undefined ? patch.year : root.frame.year,
            years: patch.years !== undefined ? patch.years : root.frame.years,
            error: patch.error !== undefined ? patch.error : root.frame.error,
            status: patch.status !== undefined ? patch.status : root.frame.status,
            lastUpdated: patch.lastUpdated !== undefined ? patch.lastUpdated : root.frame.lastUpdated
        }
    }

    function refresh() {
        // No username set: show an empty graph rather than falling back to the
        // system login's account (the fetcher would otherwise do that).
        if (!root.frame.user) {
            root.update({ status: "idle", contributions: [], total: 0, error: "" })
            return
        }
        if (fetch.running)
            root._again = true
        else
            fetch.running = true
    }

    // A manual "Sync now": bypass the script's 24h cache and hit the API.
    // Coalesced like refresh(); _force stays set until the queued runs drain.
    function forceRefresh() {
        if (!root.frame.user)
            return
        root._force = true
        root.update({ status: "loading", error: "" })
        root.refresh()
    }

    // Select a calendar year to graph; refetch it if it changes.
    function setYear(y) {
        var v = parseInt(y)
        if (!(v > 0)) return
        if (v === root.frame.year) return
        root.update({ year: v, status: "loading", error: "" })
        if (!root.frame.years || root.frame.years.length === 0)
            root.refreshYears()
        root.refresh()
    }

    // Fetch the list of years that have data for the current user.
    function refreshYears() {
        if (fetchYears.running)
            return
        if (!root.frame.user)
            return
        fetchYears.running = true
    }

    property bool _again: false
    property bool _force: false

    // Save the username to the cache and refetch for it.
    function setUser(username) {
        var u = (username || "").trim()
        if (u === "")
            return
        saveUserProcess.pendingUser = u
        saveUserProcess.running = false
        saveUserProcess.running = true
    }

    // Read the stored username; if it differs from what we're showing, refetch.
    Process {
        id: readUserProcess
        command: ["bash", "-c",
            'FILE="$1/user.txt"; if [ -f "$FILE" ]; then cat "$FILE"; fi',
            "--", root.cacheDir]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                var u = text.trim()
                if (u !== "" && u !== root.frame.user) {
                    root.update({ user: u, status: "loading", error: "" })
                    root.refreshYears()
                    root.refresh()
                }
            }
        }
    }

    Process {
        id: saveUserProcess
        property string pendingUser: ""
        command: ["bash", "-c",
            'DIR="$1"; mkdir -p "$DIR"; printf "%s" "$2" > "$DIR/user.txt"',
            "--", root.cacheDir, pendingUser]
        running: false
        onExited: {
            root.update({ user: saveUserProcess.pendingUser, status: "loading", error: "" })
            root.refreshYears()
            root.refresh()
        }
    }

    Process {
        id: fetch
        command: ["python3", "-I", root.fetcher, root.frame.user, "--year", String(root.frame.year || new Date().getFullYear())].concat(root._force ? ["--force"] : [])
        stdout: StdioCollector {
            onStreamFinished: {
                var text = this.text.trim()
                if (!text) return
                try {
                    var parsed = JSON.parse(text)
                    root.update({
                        contributions: parsed.contributions || [],
                        total: parsed.total || 0,
                        user: parsed.user || root.frame.user,
                        year: parsed.year || 0,
                        error: parsed.error || "",
                        status: parsed.error ? "error" : "loaded",
                        lastUpdated: Date.now()
                    })
                } catch (e) {
                    root.update({ status: "error", error: "Failed to parse response" })
                }
            }
        }
        onExited: {
            poll.interval = root.frame.status === "error" ? 30000 : 60000
            poll.restart()
            if (root._again) {
                // A request arrived while we were running: rerun, keeping _force
                // so a queued manual sync still bypasses the cache.
                root._again = false
                fetch.running = true
            } else {
                root._force = false
            }
        }
    }

    Process {
        id: fetchYears
        command: ["python3", "-I", root.fetcher, root.frame.user, "--years"].concat(root._force ? ["--force"] : [])
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                var t = this.text.trim()
                if (!t) return
                try {
                    var parsed = JSON.parse(t)
                    var ys = parsed.years || []
                    root.update({ years: ys })
                    var cur = root.frame.year
                    if (!(cur > 0) || ys.indexOf(cur) === -1) {
                        var pick = ys.length > 0 ? ys[ys.length - 1] : new Date().getFullYear()
                        if (pick !== cur) {
                            root.update({ year: pick, status: "loading", error: "" })
                            root.refresh()
                        }
                    }
                } catch (e) {}
            }
        }
    }

    Timer {
        id: poll
        interval: 60000
        onTriggered: root.refresh()
    }

    Component.onCompleted: {
        if (!root.frame.year)
            root.update({ year: new Date().getFullYear() })
        readUserProcess.running = true
        refresh()
    }
}
