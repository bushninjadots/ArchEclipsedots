pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Live shell geometry published by the archeclipse instance (the navbar pill
// and the left/right side panels), so the aura can attach to it. Best-effort:
// a missing, stale (>2s) or malformed bridge leaves `valid` false and every
// consumer keeps today's flat aura. Written by archeclipse's AuraBridge.
Singleton {
    id: root

    readonly property string bridgePath:
        (Quickshell.env("XDG_RUNTIME_DIR") || "/run/user/1000") + "/aura-bridge.json"

    // Parsed payload (null until a valid v1 write lands) and its freshness.
    property var _data: null
    property bool _fresh: false

    readonly property bool valid: _data !== null && _fresh

    readonly property var screen: _data ? _data.screen : null
    readonly property real screenW: (screen && screen.w !== undefined) ? screen.w : 1920
    readonly property real screenH: (screen && screen.h !== undefined) ? screen.h : 1080

    // Fail-safe geometry: pill absent (no suspension), panels collapsed to the
    // screen edges — exactly the pre-bridge look.
    readonly property var defaultLeft: ({ x: 0, y: 0, w: 0, h: root.screenH })
    readonly property var defaultRight: ({ x: root.screenW, y: 0, w: 0, h: root.screenH })

    readonly property var pill: (valid && _data.pill) ? _data.pill : null
    readonly property real barGap: (valid && _data.barGap !== undefined) ? _data.barGap : 0
    readonly property var left: (valid && _data.left) ? _data.left : defaultLeft
    readonly property var right: (valid && _data.right) ? _data.right : defaultRight

    // The shell's screen frame (archeclipse Settings -> Shell frame): the band
    // every edge reserves and its inner corner radius, 0 when the frame is off.
    readonly property var frame: (valid && _data.frame) ? _data.frame : null
    readonly property bool framed: frame !== null && frame.on === true
    readonly property real frameBand: framed ? (Number(frame.band) || 0) : 0
    readonly property real frameRadius: framed ? (Number(frame.radius) || 0) : 0

    function refreshFresh() {
        var d = root._data;
        root._fresh = d !== null && d.ts !== undefined && (Date.now() - d.ts) <= 2000;
    }

    function reparse() {
        var d = null;
        try {
            var txt = file.text();
            d = (txt && txt.length) ? JSON.parse(txt) : null;
        } catch (e) {
            d = null;
        }
        root._data = (d && d.v === 1) ? d : null;
        root.refreshFresh();
    }

    FileView {
        id: file
        path: root.bridgePath
        watchChanges: true
        printErrors: false
        onLoaded: root.reparse()
        onFileChanged: file.reload()
    }

    // watchChanges arms inotify on the path at load, so a bridge created after
    // startup is never noticed; `onFileChanged: file.reload()` carries live
    // edits, this tick ages data out and re-reads only until the first valid
    // parse (cheap, and it recovers a file created after the reader started).
    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: {
            root.refreshFresh();
            if (root._data === null || file.text().length === 0)
                file.reload();
        }
    }
}
