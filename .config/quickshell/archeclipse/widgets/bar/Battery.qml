import QtQuick
import Quickshell.Services.UPower
import qs.theme
import qs.services

// Battery for the bar: level glyph (10 steps, bolt while charging) + %,
// warm/red when low. Click opens the battery island (time left, power draw,
// health, power modes). Hidden on machines without a battery.
Rectangle {
    id: root
    width: visible ? content.width + 8 : 0
    height: Theme.barContentHeight
    radius: Theme.radius
    // flat: the bar's shared hover/pill styles it.
    property bool flat: false
    color: !root.flat && (hover.hovered || BarState.state === "battery") ? Theme.surfaceHover : "transparent"

    readonly property real pct: UPower.displayDevice?.percentage ?? 1
    readonly property bool present: UPower.displayDevice?.isLaptopBattery ?? false
    readonly property bool charging: UPower.displayDevice?.state === UPowerDeviceState.Charging
    readonly property color tone: root.charging ? "#81c784" : root.pct < 0.15 ? "#ef5350" : root.pct < 0.3 ? "#ffb74d" : Theme.fg
    visible: present

    HoverHandler {
        id: hover
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            if (BarState.state === "battery")
                BarState.deactivate("battery");
            else
                BarState.activate("battery", 0);
        }
    }

    Row {
        id: content
        anchors.centerIn: parent
        spacing: 5
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: {
                if (root.charging)
                    return "\u{F0084}";
                const steps = ["\u{F008E}", "\u{F007A}", "\u{F007B}", "\u{F007C}", "\u{F007D}", "\u{F007E}", "\u{F007F}", "\u{F0080}", "\u{F0081}", "\u{F0082}", "\u{F0079}"];
                return steps[Math.max(0, Math.min(10, Math.round(root.pct * 10)))];
            }
            color: root.tone
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize + 2
            Behavior on color {
                ColorAnimation { duration: 300 }
            }
            // Low battery: a slow pulse.
            SequentialAnimation on opacity {
                running: root.pct < 0.15 && !root.charging
                loops: Animation.Infinite
                alwaysRunToEnd: true
                NumberAnimation { to: 0.4; duration: 800 }
                NumberAnimation { to: 1; duration: 800 }
            }
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: Math.floor(root.pct * 100) + "%"
            color: Theme.fg
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
        }
    }
}
