import QtQuick
import Quickshell
import Quickshell.Io
import "qml/shell/modules/desktop"
import "qml/shell/modules/visualizer"
import "qml/shell/modules/visualizer/Singletons" as VizCfg
import shell.services as Services

// ArchEclipse desktop widgets: Ryoku's desktop widget layer (clock, calendar,
// music, notes, stats, weather, all-in-one) running as its own Quickshell
// instance, like qs-wallpaperpicker. Widgets sit on the Bottom layer, under
// windows; drag to move, right-click a widget or the bare desktop for menus.
// Settings live in ~/.config/ryoku/widgets.json. Vendored from Ryoku
// (GPL-3.0, see LICENSE and NOTICE in this folder).
ShellRoot {
    id: root

    // A still of the current wallpaper (kept by qs-wallpaperpicker), only for
    // the glass widget styles' blur; this host never paints the wallpaper.
    readonly property string wallpaperStill: "file://" + Quickshell.env("HOME") + "/.cache/current_wallpaper"

    // `ryoku-widgets editor` (ArchEclipse Settings -> Desktop Widgets) toggles
    // the editor window.
    property bool editorOpen: false
    LazyLoader {
        active: root.editorOpen
        WidgetEditor {
            onClosed: root.editorOpen = false
        }
    }
    IpcHandler {
        target: "widgets"
        function editor(): void { root.editorOpen = !root.editorOpen; }
        function openEditor(): void { root.editorOpen = true; }
        // bin/ryoku-widgets enable/disable flip this live.
        function setEnabled(on: bool): void { root.widgetsOn = on; }
        function enabled(): bool { return root.widgetsOn; }
        function editorOpen(): bool { return root.editorOpen; }
    }

    // Off (ArchEclipse Settings -> Desktop Widgets) while this marker exists;
    // the editor still opens so the widgets can be turned back on.
    property bool widgetsOn: false
    Process {
        running: true
        command: ["test", "-e", Quickshell.env("HOME") + "/.config/ryoku/widgets-disabled"]
        onExited: code => root.widgetsOn = code !== 0
    }

    Variants {
        model: Quickshell.screens

        Scope {
            id: perScreen
            required property var modelData
            readonly property var st: Services.ShellState.forScreen(perScreen.modelData)

            Desktop {
                id: desktop
                screen: perScreen.modelData
                active: root.widgetsOn
                widgetsEnabled: true
                paintWallpaper: false
                wallpaperUrl: root.wallpaperStill
                wallpaperPath: Quickshell.env("HOME") + "/.cache/current_wallpaper"
            }

            // Ryoku's audio visualizer (~/.config/ryoku/visualizer.json; the
            // desktop right-click menu and the editor tune it). Same wiring as
            // Ryoku's shell.qml; cava only runs while it is on and audio plays.
            LazyLoader {
                activeAsync: root.widgetsOn && (VizCfg.Config.enabled || (perScreen.st && perScreen.st.visualizerPlacing))
                Visualizer {
                    screen: perScreen.modelData
                    mode: !VizCfg.Config.enabled ? "off"
                        : (perScreen.st && perScreen.st.visualizerOverlay ? "overlay" : "desktop")
                    placing: perScreen.st ? perScreen.st.visualizerPlacing : false
                    suppressed: desktop.hostsVisualizer
                    onPlacingDone: if (perScreen.st) perScreen.st.visualizerPlacing = false
                }
            }
        }
    }
}
