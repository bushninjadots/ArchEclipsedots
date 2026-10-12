import QtQuick
import Quickshell
import Quickshell.Networking
import qs.theme
import qs.services
import qs.widgets.shared
import qs.widgets.bar.islands

// Network island: current connection, Wi-Fi radio switch, live scan of
// nearby networks (connected first, then saved, then by signal). Click a
// network to join it — saved/open ones connect straight away, a secured new
// one asks for its password inline. Right-click the current one to
// disconnect, a saved one to forget it.
IslandPanel {
    id: root
    stateName: "network"
    islandWidth: 360

    readonly property var devices: Networking.devices?.values ?? []
    readonly property var wifiDevice: {
        for (const d of root.devices) {
            if (d && d.type === DeviceType.Wifi)
                return d;
        }
        return null;
    }
    readonly property var wiredDevice: {
        for (const d of root.devices) {
            if (d && d.type === DeviceType.Wired)
                return d;
        }
        return null;
    }
    readonly property bool wifiOn: Networking.wifiEnabled
    readonly property var current: {
        const dev = root.wifiDevice;
        if (!dev?.networks?.values)
            return null;
        for (const nw of dev.networks.values) {
            if (nw && nw.connected)
                return nw;
        }
        return null;
    }
    readonly property bool wiredUp: !!(root.wiredDevice && root.wiredDevice.connected)
    readonly property var networks: {
        const dev = root.wifiDevice;
        if (!dev?.networks?.values)
            return [];
        const rank = n => (n.connected ? 2 : 0) + (n.known ? 1 : 0);
        return dev.networks.values.filter(n => n && (n.name ?? "") !== "")
            .slice().sort((a, b) => rank(b) - rank(a) || (b.signalStrength ?? 0) - (a.signalStrength ?? 0))
            .slice(0, 8);
    }

    // Scan only while the island is open.
    Component.onCompleted: {
        if (root.wifiDevice)
            root.wifiDevice.scannerEnabled = true;
    }
    Component.onDestruction: {
        if (root.wifiDevice)
            root.wifiDevice.scannerEnabled = false;
    }

    function strengthIcon(s, secured) {
        const i = s > 0.75 ? 4 : s > 0.5 ? 3 : s > 0.25 ? 2 : 1;
        const open = ["", "\u{F091F}", "\u{F0922}", "\u{F0925}", "\u{F0928}"];
        const lock = ["", "\u{F0921}", "\u{F0924}", "\u{F0927}", "\u{F092A}"];
        return (secured ? lock : open)[i];
    }
    function secured(n) {
        return n && n.security !== undefined && n.security !== WifiSecurityType.Open && n.security !== WifiSecurityType.Unknown;
    }

    // Network asking for a password (inline field under its row).
    property var askFor: null

    IslandHeader {
        icon: root.current ? root.strengthIcon(root.current.signalStrength ?? 0, false)
            : root.wiredUp ? "\u{F0200}" : (root.wifiOn ? "\u{F092F}" : "\u{F092E}")
        title: root.current ? root.current.name : root.wiredUp ? "Ethernet" : (root.wifiOn ? "Not connected" : "Wi-Fi off")
        subtitle: root.current ? "Connected · " + Math.round((root.current.signalStrength ?? 0) * 100) + "% signal"
            : root.wiredUp ? "Wired · " + (root.wiredDevice.linkSpeed ? root.wiredDevice.linkSpeed + " Mb/s" : root.wiredDevice.name)
            : root.wifiOn ? "Pick a network below" : "Turn Wi-Fi on to see networks"
        active: !!root.current || root.wiredUp
        IslandSwitch {
            visible: Networking.wifiHardwareEnabled !== false
            checked: root.wifiOn
            onToggled: on => Networking.wifiEnabled = on
        }
    }

    Rectangle {
        width: parent.width
        height: 1
        color: Theme.border
        visible: root.wifiOn
    }

    // Section caption with a live "scanning" pulse.
    Row {
        visible: root.wifiOn
        spacing: 6
        Text {
            text: "NETWORKS"
            color: Theme.muted
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeCaption
            font.letterSpacing: 1
        }
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: 5
            height: 5
            radius: 3
            color: Theme.accent
            SequentialAnimation on opacity {
                running: root.wifiOn
                loops: Animation.Infinite
                NumberAnimation { to: 0.2; duration: 700 }
                NumberAnimation { to: 1; duration: 700 }
            }
        }
    }

    Column {
        width: parent.width
        spacing: 3
        visible: root.wifiOn
        Repeater {
            model: root.networks
            delegate: Column {
                id: entry
                required property var modelData
                width: parent.width
                spacing: 4
                readonly property bool lock: root.secured(modelData)
                IslandRow {
                    icon: root.strengthIcon(entry.modelData.signalStrength ?? 0, entry.lock)
                    title: entry.modelData.name
                    detail: entry.modelData.stateChanging ? "Connecting…"
                        : entry.modelData.connected ? "Connected"
                        : entry.modelData.known ? "Saved" : (entry.lock ? "Secured" : "Open")
                    trailing: Math.round((entry.modelData.signalStrength ?? 0) * 100) + "%"
                    current: entry.modelData.connected
                    busy: entry.modelData.stateChanging
                    onClicked: {
                        const n = entry.modelData;
                        if (n.connected)
                            return;
                        if (n.known || !entry.lock) {
                            root.askFor = null;
                            n.connect();
                        } else {
                            root.askFor = root.askFor === n ? null : n;
                        }
                    }
                    onRightClicked: {
                        const n = entry.modelData;
                        if (n.connected)
                            n.disconnect();
                        else if (n.known)
                            n.forget();
                    }
                }
                // Password prompt for a new secured network.
                Row {
                    visible: root.askFor === entry.modelData
                    width: parent.width
                    spacing: 6
                    AppTextField {
                        id: psk
                        width: parent.width - joinBtn.width - 6
                        height: 32
                        placeholderText: "Password for " + entry.modelData.name
                        echoMode: TextInput.Password
                        onVisibleChanged: if (visible) forceActiveFocus()
                        onAccepted: joinBtn.join()
                    }
                    AppButton {
                        id: joinBtn
                        width: 64
                        height: 32
                        cornerRadius: 10
                        text: "Join"
                        idleBg: Theme.surfaceActive
                        function join() {
                            if (psk.text === "")
                                return;
                            entry.modelData.connectWithPsk(psk.text);
                            psk.text = "";
                            root.askFor = null;
                        }
                        onClicked: join()
                    }
                }
            }
        }
        Text {
            visible: root.networks.length === 0
            text: "Looking for networks…"
            color: Theme.muted
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
        }
    }

    // Wired link (when there is one).
    IslandRow {
        visible: !!root.wiredDevice
        icon: "\u{F0200}"
        title: "Ethernet"
        detail: root.wiredUp ? "Connected" : (root.wiredDevice?.hasLink ? "Cable in · not connected" : "Unplugged")
        current: root.wiredUp
    }

    Text {
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        text: "click to join · right-click to disconnect or forget"
        color: Theme.muted
        opacity: 0.7
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeCaption
    }
}
