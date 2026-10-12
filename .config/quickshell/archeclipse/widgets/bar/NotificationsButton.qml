import QtQuick
import qs.theme
import qs.services

// Notification bell: count of unread history, accent when there is any,
// bell-off glyph while Do Not Disturb is on. Click opens the right panel
// (notification centre), right-click toggles Do Not Disturb.
BarIconButton {
    id: root

    readonly property int count: (Notifications.history || []).length
    readonly property bool dnd: Settings.notifDnd

    icon: root.dnd ? "\uF1F6" : (root.count > 0 ? "\uF0F3" : "\uF0A2")
    lit: !root.dnd && root.count > 0
    badge: !root.dnd && root.count > 0 ? (root.count > 9 ? "9+" : "" + root.count) : ""
    tooltip: root.dnd ? "Do not disturb · right-click to turn off"
        : (root.count > 0 ? root.count + " notification" + (root.count === 1 ? "" : "s") : "No notifications") + " · right-click: do not disturb"

    onClicked: {
        if (BarState.rightOpen)
            BarState.deactivate("right");
        else
            BarState.activate("right", 0);
    }
    onRightClicked: Settings.updateSetting("notifications.dnd", !Settings.notifDnd)
}
