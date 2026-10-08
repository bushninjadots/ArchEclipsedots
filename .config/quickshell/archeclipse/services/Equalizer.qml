pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire

// The 10-band equalizer behind the now-playing island, ported from Ryoku's
// services/Equalizer.qml (GPL-3.0). scripts/equalizer does the work: a
// PipeWire filter-chain spliced in front of the default sink, run by the
// archeclipse-eq user unit only while the equalizer is on. Bands are live
// (one pw-cli param write per change); state persists in
// ~/.cache/quickshell/equalizer.json, which this watches.
Singleton {
    id: root

    readonly property string bin: Quickshell.env("HOME") + "/.config/quickshell/archeclipse/scripts/equalizer"
    readonly property int bandCount: 10
    readonly property var bandLabels: ["31", "63", "125", "250", "500", "1k", "2k", "4k", "8k", "16k"]
    readonly property int range: 12          // ±dB a band can travel
    readonly property var presets: ["Flat", "Bass", "Treble", "Vocal", "Pop", "Rock", "Jazz", "Classic"]

    property var gains: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
    property string preset: "Flat"
    property bool on: false
    property bool running: false

    function gainAt(i) {
        var g = root.gains;
        return (i >= 0 && i < g.length && g[i] !== undefined) ? g[i] : 0;
    }

    function run(args) {
        eqProc.running = false;
        eqProc.command = [root.bin].concat(args);
        eqProc.running = true;
        refreshTimer.restart();
    }
    // Optimistic: the island moves at once; the script's answer confirms.
    function setBand(i, db) {
        var v = Math.max(-root.range, Math.min(root.range, Math.round(db)));
        var next = root.gains.slice();
        next[i] = v;
        root.gains = next;
        root.preset = "Custom";
        root.on = true;
        root.run(["set-band", "" + (i + 1), "" + v]);
    }
    function applyPreset(name) {
        root.preset = name;
        root.run(["preset", name]);
    }
    function setOn(enabled) {
        root.on = enabled;
        root.run([enabled ? "on" : "off"]);
    }

    function ingest(text) {
        var s = ("" + text).trim();
        if (!s.length)
            return;
        var d;
        try {
            d = JSON.parse(s);
        } catch (e) {
            return;
        }
        var g = [];
        for (var i = 1; i <= root.bandCount; i++)
            g.push(Number(d["b" + i]) || 0);
        root.gains = g;
        root.preset = "" + (d.preset || "Flat");
        root.on = d.on === true;
        if (d.running !== undefined)
            root.running = d.running === true;
    }

    Process {
        id: eqProc
        stdout: StdioCollector { onStreamFinished: root.ingest(this.text) }
        stderr: StdioCollector {}
    }
    Process {
        id: getProc
        command: [root.bin, "get"]
        stdout: StdioCollector { onStreamFinished: root.ingest(this.text) }
        stderr: StdioCollector {}
    }
    function refresh() {
        getProc.running = false;
        getProc.running = true;
    }
    Timer {
        id: refreshTimer
        interval: 400
        onTriggered: root.refresh()
    }

    FileView {
        path: (Quickshell.env("XDG_CACHE_HOME") || (Quickshell.env("HOME") + "/.cache")) + "/quickshell/equalizer.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.ingest(text())
    }

    // Follow a new output device (headphones plugged in, etc.).
    readonly property string sinkName: Pipewire.defaultAudioSink ? (Pipewire.defaultAudioSink.name || "") : ""
    onSinkNameChanged: retarget.restart()
    Timer {
        id: retarget
        interval: 700
        onTriggered: if (root.on) root.run(["retarget"])
    }

    // Re-create the filter after login if it was left on.
    Component.onCompleted: root.run(["apply"])
}
