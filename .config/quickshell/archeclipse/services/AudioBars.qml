pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.theme

// Shared playback-spectrum service for the shell's music surfaces, ported
// from ryoku's services/AudioBars.qml (GPL-3) with the ryoku ties removed:
//   - Perf.pillFrozen policy -> Settings.animationsEnabled (the shell's own
//     "stillness" gate: with animations off, no surface gets a live feed)
//   - menupoll.js owner list -> inline refcount (one function, no import)
//
// One cava feed (PipeWire playback monitor, 40 bands / 30fps) serves every
// consumer — the navbar MprisWidget, the now-playing island, etc. `setActive`
// is owner-refcounted: a visible surface claims the feed, the last one to
// release stops the analyser. Levels settle flat when frames stop arriving
// (system silent, restart gap, motion disabled), so bars fall to rest
// instead of freezing on the last peak.
Singleton {
    id: root

    property var activeOwners: []
    readonly property bool active: activeOwners.length > 0
    function setActive(owner, enabled) {
        var next = [];
        var found = false;
        for (var i = 0; i < activeOwners.length; i++) {
            if (activeOwners[i] === owner)
                found = true;
            else
                next.push(activeOwners[i]);
        }
        if (enabled && !found)
            next.push(owner);
        activeOwners = next;
    }

    // The live analyser gate: an owner claims the feed, motion is allowed,
    // and (belt and braces) the service itself re-checks playback below —
    // cava emits nothing on silence, and the settle timer flattens levels.
    readonly property bool analysing: root.active && Settings.animationsEnabled

    readonly property int bars: 40
    readonly property int fps: 30

    // 0..1 per band + mean energy across all bands.
    property var levels: root.flat()
    property real energy: 0
    property real lastReadMs: 0

    function flat() {
        var a = [];
        for (var i = 0; i < root.bars; i++)
            a.push(0);
        return a;
    }

    Process {
        id: cavaProc
        // Playback spectrum via cava's native pipewire backend, source=auto
        // (the default sink's monitor). exec so quickshell's SIGTERM reaches
        // cava, leaving no orphaned analyser when the surface unloads.
        // Bound, never assigned: `running` must keep following `analysing`
        // (an imperative write here once leaked immortal analysers in ryoku —
        // see the original comment). The backoff below expresses the restart
        // without ever taking the binding away.
        running: root.analysing && !cavaProc.backoff
        // Playback spectrum from cava's PipeWire backend (the default sink's
        // monitor): raw ascii frames of `bars` values 0..100 on stdout. exec
        // so stopping the Process stops cava too.
        command: ["sh", "-c", "command -v cava >/dev/null 2>&1 || exit 0; cfg=\"${XDG_RUNTIME_DIR:-/tmp}/archeclipse-cava-bar.conf\"; printf '%s\\n' '[general]' 'framerate = " + root.fps + "' 'bars = " + root.bars + "' '' '[input]' 'method = pipewire' 'source = auto' '' '[output]' 'method = raw' 'raw_target = /dev/stdout' 'data_format = ascii' 'ascii_max_range = 100' 'channels = mono' 'mono_option = average' '' '[smoothing]' 'noise_reduction = 45' > \"$cfg\"; exec /usr/bin/cava -p \"$cfg\""]
        property bool backoff: false
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: (line) => root.readBars(line)
        }
        // cava exiting while we still want it (a transient pipewire hiccup)
        // earns one paced retry rather than a spin.
        onExited: if (root.analysing) {
            cavaProc.backoff = true;
            restartTimer.restart();
        }
    }

    Timer {
        id: restartTimer
        interval: 1200
        onTriggered: cavaProc.backoff = false
    }

    // cava sleeps and stops emitting frames once playback idles, so settle
    // back to flat when no frame has arrived recently.
    Timer {
        interval: 120
        running: root.analysing
        repeat: true
        onTriggered: if (Date.now() - root.lastReadMs > 260) {
            root.levels = root.flat();
            root.energy = 0;
        }
    }

    onAnalysingChanged: {
        levels = flat();
        energy = 0;
        if (analysing)
            lastReadMs = 0;
    }

    function norm(v) {
        var n = parseInt(v);
        if (isNaN(n))
            return 0;
        return Math.max(0, Math.min(1, n / 100));
    }

    function readBars(line) {
        var t = line.trim();
        if (!t)
            return;
        var parts = t.split(/[;\s]+/);
        if (parts.length < root.bars)
            return;
        var out = [];
        var sum = 0;
        for (var i = 0; i < root.bars; i++) {
            var v = root.norm(parts[i]);
            out.push(v);
            sum += v;
        }
        root.levels = out;
        root.energy = sum / root.bars;
        root.lastReadMs = Date.now();
    }
}
