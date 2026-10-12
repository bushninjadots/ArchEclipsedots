import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import qs.theme
import qs.services
import qs.widgets.bar.islands

// Battery island: charge level as a big gauge with the time left / to full,
// live power draw, energy and health, and the power profile switcher (when
// power-profiles-daemon is running; otherwise it says why it's missing).
IslandPanel {
    id: root
    stateName: "battery"
    islandWidth: 340

    readonly property var dev: UPower.displayDevice
    // The physical battery (health lives there, not on the display device).
    readonly property var cell: {
        for (const d of (UPower.devices?.values ?? [])) {
            if (d && d.isLaptopBattery)
                return d;
        }
        return null;
    }
    readonly property real pct: Math.max(0, Math.min(1, root.dev?.percentage ?? 0))
    readonly property int st: root.dev?.state ?? 0
    readonly property bool charging: root.st === UPowerDeviceState.Charging || root.st === UPowerDeviceState.PendingCharge
    readonly property bool full: root.st === UPowerDeviceState.FullyCharged || (root.pct >= 0.995 && !UPower.onBattery)
    readonly property real rate: Math.abs(root.dev?.changeRate ?? 0)
    readonly property color levelColor: root.pct < 0.15 ? "#ef5350" : root.pct < 0.3 ? "#ffb74d" : root.charging ? "#81c784" : Theme.accent

    function duration(sec) {
        if (!sec || sec <= 0)
            return "";
        const h = Math.floor(sec / 3600), m = Math.round((sec % 3600) / 60);
        return h > 0 ? h + " h " + (m < 10 ? "0" : "") + m + " min" : m + " min";
    }
    readonly property string statusText: {
        if (root.full)
            return "Fully charged";
        if (root.charging) {
            const t = root.duration(root.dev?.timeToFull ?? 0);
            return t ? "Charging · full in " + t : "Charging";
        }
        if (!UPower.onBattery)
            return "Plugged in · not charging";
        const t = root.duration(root.dev?.timeToEmpty ?? 0);
        return t ? t + " left" : "On battery";
    }
    function batteryIcon() {
        if (root.charging)
            return "\u{F0084}";
        const steps = ["\u{F008E}", "\u{F007A}", "\u{F007B}", "\u{F007C}", "\u{F007D}", "\u{F007E}", "\u{F007F}", "\u{F0080}", "\u{F0081}", "\u{F0082}", "\u{F0079}"];
        return steps[Math.round(root.pct * 10)];
    }

    // ---- power profiles (powerprofilesctl) ----
    property bool profilesAvailable: false
    property string profile: ""
    function refreshProfile() {
        getProc.running = true;
    }
    Process {
        id: getProc
        command: ["powerprofilesctl", "get"]
        stdout: StdioCollector {
            onStreamFinished: root.profile = text.trim()
        }
        onExited: code => root.profilesAvailable = code === 0
    }
    Process {
        id: setProc
        onExited: root.refreshProfile()
    }
    function setProfile(p) {
        root.profile = p;
        setProc.command = ["powerprofilesctl", "set", p];
        setProc.running = true;
    }
    Component.onCompleted: root.refreshProfile()

    IslandHeader {
        icon: root.batteryIcon()
        tint: root.levelColor
        title: "Battery · " + Math.round(root.pct * 100) + "%"
        subtitle: root.statusText
    }

    // Level gauge: a wide capsule with a soft glow and a charging shimmer.
    Item {
        width: parent.width
        height: 26
        Rectangle {
            id: track
            anchors.fill: parent
            radius: height / 2
            color: Theme.rgba(Theme.foreground, 0.08)
            border.width: 1
            border.color: Theme.border
            clip: true
            Rectangle {
                id: level
                width: Math.max(height, track.width * root.pct)
                height: parent.height
                radius: height / 2
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: Theme.rgba(root.levelColor, 0.55) }
                    GradientStop { position: 1; color: root.levelColor }
                }
                Behavior on width {
                    NumberAnimation { duration: 500; easing.type: Easing.OutCubic }
                }
                // Charging: a light sweep running along the fill.
                Rectangle {
                    visible: root.charging
                    width: 40
                    height: parent.height
                    radius: height / 2
                    opacity: 0.35
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0; color: "transparent" }
                        GradientStop { position: 0.5; color: "white" }
                        GradientStop { position: 1; color: "transparent" }
                    }
                    NumberAnimation on x {
                        running: root.charging
                        from: -40
                        to: level.width
                        duration: 1600
                        loops: Animation.Infinite
                    }
                }
            }
            Text {
                anchors.centerIn: parent
                text: Math.round(root.pct * 100) + "%"
                color: Theme.fg
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
                font.bold: true
                style: Text.Outline
                styleColor: Theme.rgba(Theme.background, 0.6)
            }
        }
    }

    // Stat tiles.
    Grid {
        id: tiles
        width: parent.width
        columns: 3
        spacing: 6
        readonly property real tileW: (width - spacing * 2) / 3
        Repeater {
            model: [
                { icon: "\u{F140B}", label: root.charging ? "Charge rate" : "Power draw", value: root.rate > 0 ? root.rate.toFixed(1) + " W" : "—" },
                { icon: "\u{F1211}", label: "Energy", value: root.dev && root.dev.energyCapacity > 0 ? root.dev.energy.toFixed(1) + " / " + root.dev.energyCapacity.toFixed(0) + " Wh" : "—" },
                { icon: "\u{F05F6}", label: "Health", value: root.cell && root.cell.healthSupported ? Math.round(root.cell.healthPercentage) + "%" : "—" }
            ]
            delegate: Rectangle {
                required property var modelData
                width: tiles.tileW
                height: 54
                radius: 10
                color: Theme.rgba(Theme.foreground, 0.05)
                border.width: 1
                border.color: Theme.border
                Column {
                    anchors.left: parent.left
                    anchors.leftMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2
                    Text {
                        text: modelData.icon + "  " + modelData.label
                        color: Theme.muted
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeCaption
                    }
                    Text {
                        text: modelData.value
                        color: Theme.fg
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize
                        font.bold: true
                    }
                }
            }
        }
    }

    // Power profile switcher.
    Column {
        width: parent.width
        spacing: 6
        Text {
            text: "POWER MODE"
            color: Theme.muted
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeCaption
            font.letterSpacing: 1
        }
        Row {
            id: modes
            visible: root.profilesAvailable
            width: parent.width
            spacing: 6
            Repeater {
                model: [
                    { id: "power-saver", icon: "\u{F032A}", label: "Saver" },
                    { id: "balanced", icon: "\u{F05D1}", label: "Balanced" },
                    { id: "performance", icon: "\u{F04C5}", label: "Performance" }
                ]
                delegate: Rectangle {
                    required property var modelData
                    readonly property bool on: root.profile === modelData.id
                    width: (modes.width - modes.spacing * 2) / 3
                    height: 34
                    radius: 10
                    color: on ? Theme.rgba(Theme.accent, 0.22) : (pm.containsMouse ? Theme.rgba(Theme.foreground, 0.08) : Theme.rgba(Theme.foreground, 0.04))
                    border.width: 1
                    border.color: on ? Theme.accent : Theme.border
                    scale: pm.pressed ? 0.96 : 1
                    Behavior on scale {
                        NumberAnimation { duration: 140; easing.type: Easing.OutBack; easing.overshoot: 2 }
                    }
                    Behavior on color {
                        ColorAnimation { duration: 150 }
                    }
                    Text {
                        anchors.centerIn: parent
                        text: modelData.icon + " " + modelData.label
                        color: parent.on ? Theme.accent : Theme.fg
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSmall
                        font.bold: parent.on
                    }
                    MouseArea {
                        id: pm
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.setProfile(modelData.id)
                    }
                }
            }
        }
        Text {
            visible: !root.profilesAvailable
            width: parent.width
            wrapMode: Text.WordWrap
            text: "Power modes need power-profiles-daemon (it isn't running here)."
            color: Theme.muted
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
        }
    }
}
