import QtQuick
import Quickshell.Bluetooth
import qs.theme
import qs.services

// Bluetooth status for the bar: off / on / connected glyph (headphones when
// an audio device is connected), lit while something is connected, with the
// device count as a badge when there are several. Click opens the Bluetooth
// island, right-click toggles the adapter.
BarIconButton {
    id: root

    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property bool powered: root.adapter?.enabled ?? false
    readonly property var connected: (root.adapter?.devices?.values ?? []).filter(d => d && d.connected)
    readonly property bool audio: root.connected.some(d => /audio|headset|headphone|speaker/i.test(d.icon ?? ""))
    readonly property var withBattery: root.connected.filter(d => d.batteryAvailable)

    visible: !!root.adapter
    icon: !root.powered ? "\u{F00B2}" : root.audio ? "\u{F00B0}" : root.connected.length > 0 ? "\u{F00B1}" : "\u{F00AF}"
    lit: root.connected.length > 0
    opacity: root.powered ? 1 : 0.55
    badge: root.connected.length > 1 ? "" + root.connected.length : ""
    // One connected device with a battery: show its level beside the glyph.
    label: root.connected.length === 1 && root.withBattery.length === 1 ? Math.round(root.withBattery[0].battery * 100) + "%" : ""
    tooltip: !root.powered ? "Bluetooth off · right-click to turn on"
        : root.connected.length > 0 ? root.connected.map(d => d.name).join(", ") : "Bluetooth on · no devices"

    onClicked: {
        if (BarState.state === "bluetooth")
            BarState.deactivate("bluetooth");
        else
            BarState.activate("bluetooth", 0);
    }
    onRightClicked: {
        if (root.adapter)
            root.adapter.enabled = !root.adapter.enabled;
    }
}
