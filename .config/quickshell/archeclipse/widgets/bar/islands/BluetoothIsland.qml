import QtQuick
import Quickshell
import Quickshell.Bluetooth
import qs.theme
import qs.services
import qs.widgets.bar.islands

// Bluetooth island: adapter power switch, connected devices on top (with
// their battery), then paired, then anything found by a scan. Click a device
// to connect / disconnect (pairs first when needed); right-click a paired
// one to forget it. Scans only while the island is open.
IslandPanel {
    id: root
    stateName: "bluetooth"
    islandWidth: 360

    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property bool available: !!root.adapter
    readonly property bool powered: root.adapter?.enabled ?? false
    readonly property var devices: {
        const list = root.adapter?.devices?.values ?? [];
        const rank = d => (d.connected ? 4 : 0) + (d.paired || d.bonded ? 2 : 0) + (d.name !== d.address ? 1 : 0);
        return list.filter(d => d && !d.blocked).slice().sort((a, b) => rank(b) - rank(a)).slice(0, 10);
    }
    readonly property var connected: root.devices.filter(d => d.connected)

    Component.onCompleted: {
        if (root.powered)
            root.adapter.discovering = true;
    }
    Component.onDestruction: {
        if (root.adapter && root.adapter.discovering)
            root.adapter.discovering = false;
    }
    onPoweredChanged: {
        if (root.powered && root.adapter)
            root.adapter.discovering = true;
    }

    // Device glyph from its BlueZ icon name.
    function deviceIcon(d) {
        const i = (d?.icon ?? "").toLowerCase();
        if (i.includes("headset") || i.includes("headphone"))
            return "\u{F02CB}";
        if (i.includes("audio") || i.includes("speaker"))
            return "\u{F04C3}";
        if (i.includes("phone"))
            return "\u{F011C}";
        if (i.includes("mouse"))
            return "\u{F037D}";
        if (i.includes("keyboard"))
            return "\u{F030C}";
        if (i.includes("gaming") || i.includes("joystick"))
            return "\u{F0296}";
        if (i.includes("video") || i.includes("display"))
            return "\u{F0502}";
        if (i.includes("computer"))
            return "\u{F0322}";
        if (i.includes("watch"))
            return "\u{F0897}";
        return "\u{F00AF}";
    }
    function stateText(d) {
        if (d.pairing)
            return "Pairing…";
        if (d.state === BluetoothDeviceState.Connecting)
            return "Connecting…";
        if (d.state === BluetoothDeviceState.Disconnecting)
            return "Disconnecting…";
        if (d.connected)
            return "Connected" + (d.batteryAvailable ? " · battery " + Math.round(d.battery * 100) + "%" : "");
        if (d.paired || d.bonded)
            return "Paired";
        return "Nearby";
    }

    IslandHeader {
        icon: !root.powered ? "\u{F00B2}" : root.connected.length > 0 ? "\u{F00B1}" : "\u{F00AF}"
        title: !root.available ? "No Bluetooth adapter" : !root.powered ? "Bluetooth off"
            : root.connected.length === 1 ? root.connected[0].name
            : root.connected.length > 1 ? root.connected.length + " devices connected" : "Bluetooth on"
        subtitle: !root.available ? "bluetoothd isn't running"
            : !root.powered ? "Turn it on to connect devices"
            : root.connected.length > 0 ? root.stateText(root.connected[0])
            : (root.adapter.discovering ? "Scanning for devices…" : "No device connected")
        active: root.powered
        IslandSwitch {
            visible: root.available
            checked: root.powered
            onToggled: on => root.adapter.enabled = on
        }
    }

    Rectangle {
        width: parent.width
        height: 1
        color: Theme.border
        visible: root.powered
    }

    Row {
        visible: root.powered
        spacing: 6
        Text {
            text: "DEVICES"
            color: Theme.muted
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeCaption
            font.letterSpacing: 1
        }
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.adapter?.discovering ?? false
            width: 5
            height: 5
            radius: 3
            color: Theme.accent
            SequentialAnimation on opacity {
                running: root.adapter?.discovering ?? false
                loops: Animation.Infinite
                NumberAnimation { to: 0.2; duration: 700 }
                NumberAnimation { to: 1; duration: 700 }
            }
        }
    }

    Column {
        width: parent.width
        spacing: 3
        visible: root.powered
        Repeater {
            model: root.devices
            delegate: IslandRow {
                id: dev
                required property var modelData
                icon: root.deviceIcon(modelData)
                title: modelData.name || modelData.address
                detail: root.stateText(modelData)
                current: modelData.connected
                busy: modelData.pairing || modelData.state === BluetoothDeviceState.Connecting
                    || modelData.state === BluetoothDeviceState.Disconnecting
                // Battery chip for connected devices that report one.
                Rectangle {
                    visible: dev.modelData.connected && dev.modelData.batteryAvailable
                    width: batt.implicitWidth + 12
                    height: 18
                    radius: 9
                    color: Theme.rgba(Theme.accent, 0.16)
                    Text {
                        id: batt
                        anchors.centerIn: parent
                        text: Math.round((dev.modelData.battery ?? 0) * 100) + "%"
                        color: Theme.accent
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeCaption
                    }
                }
                onClicked: {
                    const d = dev.modelData;
                    if (d.connected)
                        d.disconnect();
                    else if (d.paired || d.bonded) {
                        d.trusted = true;
                        d.connect();
                    } else
                        d.pair();
                }
                onRightClicked: {
                    if (dev.modelData.paired || dev.modelData.bonded)
                        dev.modelData.forget();
                }
            }
        }
        Text {
            visible: root.devices.length === 0
            text: "No devices yet — put yours in pairing mode"
            color: Theme.muted
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
        }
    }

    Text {
        visible: root.powered
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        text: "click to connect or disconnect · right-click to forget"
        color: Theme.muted
        opacity: 0.7
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeCaption
    }
}
