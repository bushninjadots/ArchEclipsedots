import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.theme
import qs.services

// Focused window: app glyph + title (elided). Click opens the overview,
// middle-click closes the window.
BarIconButton {
    id: root

    readonly property var win: Hyprland.activeToplevel
    readonly property string cls: (root.win?.lastIpcObject?.class ?? "") + ""
    readonly property string title: ((root.win?.title ?? "") + "").trim()
    property int maxChars: 42

    visible: root.title !== ""
    icon: root.cls !== "" ? WorkspaceIcons.forClientClass(root.cls) : WorkspaceIcons.emptyIcon
    label: root.title.length > root.maxChars ? root.title.substring(0, root.maxChars - 1) + "…" : root.title
    tooltip: root.title.length > root.maxChars ? root.title : ""

    onClicked: {
        if (BarState.state === "overview")
            BarState.deactivate("overview");
        else
            BarState.activate("overview", 0);
    }
    onMiddleClicked: Hyprland.dispatch("hl.dsp.window.close()")
}
