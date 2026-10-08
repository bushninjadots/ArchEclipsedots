pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "lib/weather.js" as Model

// QML view of a weather frame. In Ryoku the ryoku-shell daemon streams it over
// a socket; ArchEclipse has no daemon, so bin/ryoku-weather (a Python port of
// its weather.go: Open-Meteo, keyless) prints the same frame and this runs it
// every 15 minutes and whenever the place or unit changes. This singleton just
// parses the frame and re-exposes it, deriving the compact glyph and short label
// for the quick-settings and calendar views from the WMO code.
Singleton {
    id: root

    readonly property string fetcher: Quickshell.env("HOME") + "/.config/ryoku-widgets/bin/ryoku-weather"

    // The whole frame, plus the parts callers bind directly.
    property var frame: ({ status: "loading", hourly: [], daily: [] })
    readonly property string status: frame.status || "loading"
    readonly property string errorKind: frame.errorKind || ""
    readonly property string errorText: frame.error || ""
    readonly property string location: frame.location || ""
    readonly property bool hasData: frame.hasData === true
    readonly property var current: frame.current || null
    readonly property var hourly: frame.hourly || []
    readonly property var daily: frame.daily || []
    readonly property var moon: frame.moon || null
    readonly property var air: frame.air || null
    readonly property string updatedAt: frame.updatedAt || ""

    // Compact contract for the quick-settings and calendar views, derived from
    // the full weather frame.
    readonly property bool available: root.status === "loaded" && root.current !== null
    readonly property string temp: root.current ? root.current.temperature : ""
    readonly property int tempNow: root.current ? root.current.temp : 0
    readonly property int humidity: root.current ? root.current.humidity : 0
    readonly property int wind: root.current ? root.current.windValue : 0
    readonly property int feels: root.current ? root.current.feels : 0
    readonly property bool isDay: root.current ? root.current.isDay : true
    readonly property string city: frame.city || ""
    readonly property string condition: root.current ? Model.labelFor(root.current.code) : ""
    readonly property string glyph: root.current ? Model.glyphFor(root.current.code) : "cloud"

    function apply(line) {
        try {
            const f = JSON.parse(line);
            if (!Array.isArray(f.hourly))
                f.hourly = [];
            if (!Array.isArray(f.daily))
                f.daily = [];
            root.frame = f;
        } catch (e) {
            // A malformed frame must never wedge the readout; keep the last good one.
        }
    }

    // The error-state Retry button fetches again now.
    function retry() { root.refresh(); }

    // Switch the temperature unit from the surface: persist it and re-fetch.
    function setUnit(unit) {
        Config.weatherUnit = unit;
        root.refresh();
    }

    function refresh() {
        if (fetch.running)
            root._again = true;
        else
            fetch.running = true;
    }
    property bool _again: false

    Connections {
        target: Config
        function onWeatherLocationChanged() { root.refresh(); }
        function onWeatherUnitChanged() { root.refresh(); }
    }

    Process {
        id: fetch
        command: ["python3", "-I", root.fetcher, Config.weatherLocation || "", Config.weatherUnit || "auto"]
        stdout: StdioCollector {
            onStreamFinished: if (text.trim().length) root.apply(text.trim())
        }
        onExited: {
            // Errors retry sooner (30s, like the daemon's recover interval).
            poll.interval = root.status === "error" ? 30000 : 15 * 60000;
            poll.restart();
            if (root._again) {
                root._again = false;
                fetch.running = true;
            }
        }
    }

    Timer {
        id: poll
        interval: 15 * 60000
        onTriggered: root.refresh()
    }

    Component.onCompleted: root.refresh()
}
