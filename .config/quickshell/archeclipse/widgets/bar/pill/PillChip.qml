import QtQuick
import Quickshell
import Quickshell.Services.Mpris
import Quickshell.Services.UPower
import qs.theme
import qs.services
import qs.widgets.shared

// Live chip for the pill bar style. Media-forward: shows now-playing while
// a player is active, otherwise the battery. A live track tints the chip with
// a faint accent plate; hovering always lifts it. Clicking opens the matching
// island (player when media is live, control otherwise) through the same
// BarState machine every other bar face uses.
Rectangle {
    id: root

    property var player: null
    readonly property bool hasMedia: player !== null
    readonly property real pct: UPower.displayDevice?.percentage ?? 0
    readonly property bool charging: UPower.displayDevice?.state === UPowerDeviceState.Charging

    implicitWidth: row.implicitWidth + 22
    implicitHeight: Theme.barContentHeight + 8
    width: implicitWidth
    height: implicitHeight
    radius: height / 2
    color: mouse.containsMouse ? Theme.surfaceHover : (root.hasMedia ? Theme.rgba(Theme.accent, 0.16) : "transparent")
    Behavior on color {
        CAnim {}
    }
    Behavior on implicitWidth {
        Anim {
            type: Anim.FastSpatial
        }
    }

    function batteryGlyph() {
        if (charging)
            return "\uf0e7";
        if (pct > 0.9)
            return "\uf240";
        if (pct > 0.7)
            return "\uf241";
        if (pct > 0.5)
            return "\uf242";
        if (pct > 0.25)
            return "\uf243";
        return "\uf244";
    }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 7

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.hasMedia ? "\uf001" : root.batteryGlyph()
            color: root.hasMedia ? Theme.accent : (root.pct < 0.15 ? "#a94545" : Theme.fg)
            font.pixelSize: Theme.fontSize
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.hasMedia ? ((root.player && root.player.trackTitle) || "Playing") : Math.round(root.pct * 100) + "%"
            color: root.hasMedia ? Theme.fg : Theme.muted
            font.pixelSize: Theme.fontSize
            elide: Text.ElideRight
            width: Math.min(implicitWidth, 150)
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.hasMedia && root.player && (root.player.trackArtist ?? "") !== ""
            text: (root.player && root.player.trackArtist) || ""
            color: Theme.muted
            font.pixelSize: Math.max(Theme.fontSize - 1, 8)
            elide: Text.ElideRight
            width: visible ? Math.min(implicitWidth, 120) : 0
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton
        onClicked: {
            if (root.hasMedia) {
                if (BarState.state === "player")
                    BarState.deactivate("player");
                else
                    BarState.activate("player");
            } else {
                if (BarState.state === "control")
                    BarState.deactivate("control");
                else
                    BarState.activate("control", 0);
            }
        }
    }
}
