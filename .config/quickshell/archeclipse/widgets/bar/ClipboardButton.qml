import QtQuick
import qs.theme
import qs.services

// Clipboard history: opens the launcher pre-filled with the clipboard
// search ("cb "); right-click opens the emoji picker the same way.
BarIconButton {
    id: root
    icon: "\uF0EA"
    tooltip: "Clipboard history \u00B7 right-click: emoji"
    function _open(q) {
        if ("search" in BarState.activeStates) {
            Launcher.fillInputRequested(q);
            Launcher.runQuery(q);
        } else {
            Launcher.pendingQuery = q;
            BarState.activate("search", 0);
        }
    }
    onClicked: root._open("cb ")
    onRightClicked: root._open("emoji ")
}
