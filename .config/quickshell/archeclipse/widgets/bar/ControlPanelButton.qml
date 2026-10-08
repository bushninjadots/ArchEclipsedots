import QtQuick
import Quickshell
import qs.services
import qs.theme

// Port of Utilities.tsx ControlPanelButton — toggles the control island
// (quick settings) in the bar pill.
Rectangle {
    id: root

    width: 32
    height: Theme.barContentHeight
    radius: Theme.radius
    color: mouse.containsMouse ? Theme.surfaceHover : "transparent"

    Text {
        anchors.centerIn: parent
        text: "\uf303"
        color: Theme.fg
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize + 1
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            // Toggle the control island in the bar pill.
            if (BarState.state === "control")
                BarState.deactivate("control");
            else
                BarState.activate("control", 0);
        }
    }
}
