import QtQuick
import Quickshell.Hyprland
import qs.theme
import qs.widgets.shared

// Compact workspace dots for the pill bar style. One dot per workspace
// 1..count: the focused workspace widens into an accent capsule, occupied
// workspaces pick up the foreground tint, empty ones fall back to the border
// token. Click focuses the workspace (same hl.dsp.focus dispatcher as the
// strip widget).
Row {
    id: root

    property int count: 5
    property int dotSize: 5

    width: implicitWidth
    height: implicitHeight
    spacing: 5

    Repeater {
        model: root.count

        Rectangle {
            required property int index
            readonly property int ws: index + 1
            readonly property bool focused: !!Hyprland.focusedWorkspace && Hyprland.focusedWorkspace.id === ws
            readonly property bool occupied: {
                try {
                    return (Hyprland.workspaces.values || []).some(w => w.id === ws);
                } catch (e) {
                    return false;
                }
            }

            width: focused ? root.dotSize * 2.4 : root.dotSize
            height: root.dotSize
            radius: height / 2
            color: focused ? Theme.accent : (occupied ? Theme.fg : Theme.border)
            Behavior on width {
                Anim {
                    type: Anim.FastSpatial
                }
            }
            Behavior on color {
                CAnim {}
            }

            MouseArea {
                anchors.centerIn: parent
                width: parent.width + 8
                height: parent.height + 10
                acceptedButtons: Qt.LeftButton
                onClicked: Hyprland.dispatch("hl.dsp.focus({ workspace = " + (index + 1) + " })")
            }
        }
    }
}
