import QtQuick
import Quickshell
import Quickshell.Services.Pipewire
import qs.theme

// Microphone: default source mute toggle. Red while muted; wheel adjusts the
// input level; right-click opens pavucontrol on the input tab.
BarIconButton {
    id: root

    readonly property PwNode source: Pipewire.defaultAudioSource
    PwObjectTracker {
        objects: [root.source]
    }
    readonly property bool ready: !!root.source?.audio
    readonly property bool muted: root.ready && root.source.audio.muted
    readonly property int level: root.ready ? Math.round((root.source.audio.volume || 0) * 100) : 0

    visible: root.ready
    icon: root.muted ? "\uF131" : "\uF130"
    alert: root.muted
    tooltip: root.muted ? "Microphone muted" : "Microphone " + root.level + "%"
    onClicked: if (root.ready) root.source.audio.muted = !root.source.audio.muted
    onWheel: delta => {
        if (!root.ready)
            return;
        const v = Math.max(0, Math.min(1.5, root.source.audio.volume + (delta > 0 ? 0.05 : -0.05)));
        root.source.audio.volume = v;
    }
    onRightClicked: Quickshell.execDetached(["pavucontrol", "--tab=4"])
}
