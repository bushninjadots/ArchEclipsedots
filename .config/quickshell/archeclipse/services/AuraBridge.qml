pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.theme

// Publishes the shell's live geometry (navbar pill + side panels) for the
// desktop-widgets "aura" visualiser, which runs in a separate Quickshell
// process and cannot see the bar or panels otherwise. Bar.qml feeds the
// rects; every change marks the snapshot dirty and a throttling 16 ms timer
// writes it once, so a per-frame unfold costs at most one write per frame.
// A 1 s heartbeat keeps `ts` fresh while this process is alive — the reader
// treats a bridge older than 2 s as dead, so without it an idle bar would
// silently detach the aura (a dead shell stops heartbeating and falls back).
Singleton {
    id: root

    // Fed by Bar.qml. Rects are in root.contentItem logical px; {x, y, w, h}.
    property var pillRect: ({ x: 0, y: 0, w: 0, h: 0, r: 0 })
    property var leftRect: ({ x: 0, y: 0, w: 0, h: root.screenH })
    property var rightRect: ({ x: root.screenW, y: 0, w: 0, h: root.screenH })
    // False while the bar is auto-hidden, so the aura drops its suspension.
    property bool pillShown: true
    property real barGap: 0
    property real screenW: 1920
    property real screenH: 1080
    property real screenScale: 1

    property bool dirty: false

    readonly property string bridgePath:
        (Quickshell.env("XDG_RUNTIME_DIR") || "/run/user/1000") + "/aura-bridge.json"

    onPillRectChanged: poke()
    onLeftRectChanged: poke()
    onRightRectChanged: poke()
    onPillShownChanged: poke()
    onBarGapChanged: poke()
    onScreenWChanged: poke()
    onScreenHChanged: poke()
    onScreenScaleChanged: poke()
    // The shell frame, so the aura can start at its inner line.
    readonly property bool frameOn: Settings.shellFrame
    readonly property real frameBand: Settings.frameThickness
    readonly property real frameRadius: Settings.frameRadius
    onFrameOnChanged: poke()
    onFrameBandChanged: poke()
    onFrameRadiusChanged: poke()

    function poke() {
        root.dirty = true;
        // Throttle (not debounce): during a fast unfold a 16 ms restart would
        // starve the write on high-refresh displays, so only arm when idle.
        if (!writeTimer.running)
            writeTimer.start();
    }

    function snapshot() {
        const p = root.pillRect || {};
        const l = root.leftRect || {};
        const r = root.rightRect || {};
        return {
            v: 1,
            ts: Date.now(),
            screen: { w: root.screenW, h: root.screenH, scale: root.screenScale },
            barGap: root.barGap,
            frame: { on: root.frameOn, band: root.frameBand, radius: root.frameRadius },
            pill: {
                x: p.x || 0, y: p.y || 0, w: p.w || 0, h: p.h || 0,
                r: p.r || 0, shown: root.pillShown
            },
            left: { x: l.x || 0, y: l.y || 0, w: l.w || 0, h: l.h || root.screenH },
            right: {
                x: (r.x === undefined ? root.screenW : r.x),
                y: r.y || 0, w: r.w || 0, h: r.h || root.screenH
            }
        };
    }

    // Heartbeat: keeps `ts` fresh while this process runs so an idle bar's
    // geometry is not mistaken for a dead writer (one tiny write per second).
    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: root.poke()
    }

    Timer {
        id: writeTimer
        interval: 16
        repeat: false
        onTriggered: {
            if (!root.dirty)
                return;
            root.dirty = false;
            bridgeFile.setText(JSON.stringify(root.snapshot()));
        }
    }

    property FileView bridgeFile: FileView {
        path: root.bridgePath
        atomicWrites: true
    }
}
