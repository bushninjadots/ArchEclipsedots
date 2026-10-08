import QtQuick
import Quickshell
import Eclipse.Ui.Singletons
// Imported so Quickshell indexes the Hub folders (their files use each other
// as same-folder types).
import "qml/hub" as Hub
import "qml/hub/pages" as HubPages

// The widget editor: the Ryoku Hub's "Desktop Widgets" page in its own window.
// It edits ~/.config/desktop-widgets/settings/widgets.json with a Save/Revert draft; the desktop
// layer watches that file, so a save shows on the desktop at once.
FloatingWindow {
    id: win
    title: "Desktop Widgets"
    implicitWidth: 1180
    implicitHeight: 780
    // ArchEclipse panel translucency (Settings -> Interface -> Opacity); the
    // floor never drops below 0.85 so the cards stay readable over windows.
    color: Qt.rgba(Tokens.paper.r, Tokens.paper.g, Tokens.paper.b, Math.max(0.85, Tokens.archOpacity))

    // The bits of the Hub the page asks for (its search query and the
    // advanced-settings toggle).
    QtObject {
        id: hubStub
        property string query: ""
        property bool advanced: true
    }

    Loader {
        anchors.fill: parent
        source: Qt.resolvedUrl("qml/hub/pages/WidgetsPage.qml")
        onLoaded: item.hub = hubStub
    }
}
