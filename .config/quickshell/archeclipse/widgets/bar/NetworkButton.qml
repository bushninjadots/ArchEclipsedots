import QtQuick
import Quickshell.Networking
import qs.theme
import qs.services

// Compact network status for the bar: signal-strength bars / ethernet plug
// (+ SSID on right-click). Click opens the network island.
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

    readonly property bool wifiOff: !Networking.wifiEnabled
    // Wi-Fi bars follow signal strength; wired shows the ethernet plug.
    icon: !root.connected ? (root.wifiOff ? "\u{F092E}" : "\u{F092F}")
        : !root.isWifi ? "\u{F0200}"
        : root.signal > 75 ? "\u{F0928}" : root.signal > 50 ? "\u{F0925}" : root.signal > 25 ? "\u{F0922}" : "\u{F091F}"
    lit: root.connected && !root.isWifi
    alert: !root.connected && !root.wifiOff
    opacity: root.wifiOff && !root.connected ? 0.55 : 1
    label: root.showName && root.connected ? root.name : ""
    tooltip: !root.connected ? (root.wifiOff ? "Wi-Fi off" : "Offline")
        : root.isWifi ? root.name + " · " + root.signal + "%" : "Wired · " + root.name
    onClicked: {
        if (BarState.state === "network")
            BarState.deactivate("network");
        else
            BarState.activate("network", 0);
    }
    onRightClicked: root.showName = !root.showName
}
