import QtQuick
import Quickshell
import qs.theme
import qs.services

// Screen recorder: record button at rest; while recording a pulsing red dot
// with the elapsed time. Click starts a full-screen recording (or stops),
// right-click records an area.
BarIconButton {
    id: root

    readonly property bool rec: ScreenRecorder.isRecording
    property double now: Date.now()
    Timer {
        interval: 1000
        repeat: true
        running: root.rec
        triggeredOnStart: true
        onTriggered: root.now = Date.now()
    }
    function _elapsed() {
        const s = Math.max(0, Math.floor((root.now - ScreenRecorder.startTimestamp) / 1000));
        const m = Math.floor(s / 60);
        return m + ":" + String(s % 60).padStart(2, "0");
    }

    icon: root.rec ? "\uF111" : "\uF03D"
    label: root.rec && ScreenRecorder.startTimestamp > 0 ? root._elapsed() : ""
    alert: root.rec
    tooltip: root.rec ? "Recording · click to stop" : "Record screen · right-click: area"
    onClicked: ScreenRecorder.toggleRecording("")
    onRightClicked: if (!root.rec) ScreenRecorder.toggleRecording("area")

    // Gentle pulse while recording.
    SequentialAnimation on opacity {
        running: root.rec
        loops: Animation.Infinite
        NumberAnimation { to: 0.55; duration: 700; easing.type: Easing.InOutSine }
        NumberAnimation { to: 1; duration: 700; easing.type: Easing.InOutSine }
        onRunningChanged: if (!running) root.opacity = 1
    }
}
