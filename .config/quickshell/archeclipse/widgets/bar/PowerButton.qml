import QtQuick
import Quickshell
import qs.theme

// Session: click opens the power menu (wlogout), right-click locks now.
BarIconButton {
    id: root
    icon: "\uF011"
    tooltip: "Power menu · right-click: lock"
    onClicked: Quickshell.execDetached(["wlogout", "-b", "5", "-p", "layer-shell"])
    onRightClicked: Quickshell.execDetached(["loginctl", "lock-session"])
}
