import QtQuick
import Quickshell
import qs.theme

// Screenshot: click captures an area, right-click the whole screen
// (~/.config/hypr/scripts/screenshot.sh, which copies + notifies).
BarIconButton {
    id: root
    readonly property string script: Quickshell.env("HOME") + "/.config/hypr/scripts/screenshot.sh"
    icon: "\uF030"
    tooltip: "Screenshot area \u00B7 right-click: full screen"
    onClicked: Quickshell.execDetached([root.script, "--area"])
    onRightClicked: Quickshell.execDetached([root.script, "--now"])
}
