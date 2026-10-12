import QtQuick
import Quickshell.Networking
import qs.theme
import qs.services

// Compact network status for the bar: signal glyph (+ SSID when there is
// room), dimmed and struck when offline. Click opens the network island.
BarIconButton {
    id: root

    property bool showName: false

    readonly property var device: {
        if (!Networking.devices?.values)
            return null;
        for (const d of Networking.devices.values) {
            if (d && d.connected)
                return d;
        }
        return Networking.devices.values.length > 0 ? Networking.devices.values[0] : null;
    }
    readonly property bool connected: root.device?.connected ?? false
    readonly property bool isWifi: root.device?.type === DeviceType.Wifi
    readonly property var network: {
        if (!root.isWifi || !root.device?.networks?.values)
            return null;
        for (const nw of root.device.networks.values) {
            if (nw && nw.connected)
                return nw;
        }
        return null;
    }
    readonly property int signal: root.network ? Math.round((root.network.signalStrength ?? 0) * 100) : 0
    readonly property string name: root.network?.name ?? (root.device?.name ?? "")

    icon: !root.connected ? "\uF127"
        : !root.isWifi ? "\uF0E8"
        : "\uF1EB"
    alert: !root.connected
    label: root.showName && root.connected ? root.name : ""
    tooltip: !root.connected ? "Offline"
        : root.isWifi ? root.name + " · " + root.signal + "%" : "Wired · " + root.name
    // Weak wifi reads dimmer.
    opacity: root.connected && root.isWifi ? 0.55 + 0.45 * Math.min(1, root.signal / 60) : 1
    onClicked: BarState.activate("network", 3000)
    onRightClicked: root.showName = !root.showName
}
