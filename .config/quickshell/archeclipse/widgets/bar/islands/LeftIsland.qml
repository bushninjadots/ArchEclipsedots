import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services
import qs.widgets.bar.islands
import qs.widgets.leftPanel

// LeftIsland: the former LeftPanel body (sidebar + widget stack) living
// in the left side pill beside the bar (BarState.leftOpen flag).
//
// Same unfold pattern as Search/ControlIsland — the pill grows
// (width via the pill transition, height snapped on the window) while this
// body unfolds via the expand driver (clip + opacity + scale only, so no
// expensive layout animates per-frame). Each tab is a Loader that builds
// on first select and stays alive, so switches preserve state exactly
// like the old panel while opening builds only one widget.
//
// Open: SUPER+L bind, left HotZone hover, launcher quick-app, IPC.
// Close: bind toggle, Esc, close button, or 1s after the cursor leaves
// (Settings.leftPanelLock pins it open).
Item {
    id: root
    width: Settings.leftPanelWidth
    // Explicit full height (NOT implicit): positioner implicit sizes freeze
    // at completion-time values in this engine, so a height driven only by
    // the expand animation would never reach the pill — the Loader measures
    // this explicit height and the pill snaps to it, exactly like the
    // static DefaultBar/PlayerIsland pages. The expand driver below still
    // unfolds the content inside the snapped pill (clip + opacity + scale).
    height: bodyHeight

    // Island owner passes the bar's monitor; body falls back to focused.
    property string monitorName: ""
    // Monitor screen object (ShellScreen) passed by the bar owner.
    property var screen: null

    // Full monitor height, passed by the bar owner. Side islands stretch
    // the whole vertical screen like the old edge panels did (the pill
    // adds its 10px padding, leaving a 5px bottom margin).
    property int screenHeight: (screen && screen.height > 0) ? screen.height : 1080

    // Fixed dropdown height (the old panel stretched full monitor height;
    // the island is a floating card — each widget fills this viewport and
    // scrolls internally, same as the search island's fixed body height).
    property int bodyHeight: Math.max(400, screenHeight - 15)

    // Expand driver: 0 -> 1 on creation unfolds the body.
    property real expand: 0
    // Tab-name order for the selector-rail index mapping (the rail's
    // own model below carries the verbatim name+icon items; names keep
    // the QS "Widget" suffix for IPC showWidget/widgetState compat).
    readonly property var tabOrder: ["About", "ChatBot", "SettingsWidget", "CustomScripts", "KeyBinds"]
    function tabIndex(name) {
        return Math.max(0, root.tabOrder.indexOf(name));
    }
    Component.onCompleted: {
        expand = 1;
        Registry.register(root.registryKey(), root);
        Registry.register("left-island", root);
        // Prime the initially-selected tab so its Loader activates below.
        var v = Object.assign({}, root._visited);
        v[root.selectedWidget] = true;
        root._visited = v;
    }
    onMonitorNameChanged: {
        if (root.monitorName !== "")
            Registry.register(root.registryKey(), root);
    }
    Component.onDestruction: {
        Registry.unregister("left-island");
        Registry.unregister(root.registryKey());
    }
    function registryKey() {
        return `left-island-${root.monitorName || Registry.monitorName}`;
    }

    // Selected widget — initialized from persisted Settings and written
    // back on change (same contract the panel had).
    property string selectedWidget: Settings.leftPanelWidget
    // Tabs visited this session — a tab's Loader activates on first select
    // and stays active (object replaced, never mutated, for change notify).
    property var _visited: ({})
    function tabPrimed(name) {
        return root.selectedWidget === name || root._visited[name] === true;
    }
    onSelectedWidgetChanged: {
        if (Settings.leftPanelWidget !== selectedWidget)
            Settings.leftPanelWidget = selectedWidget;
        if (root._visited[selectedWidget] !== true) {
            var v = Object.assign({}, root._visited);
            v[selectedWidget] = true;
            root._visited = v;
        }
        switchAnim.restart();
    }
    Connections {
        target: Settings
        function onLeftPanelWidgetChanged() {
            if (root.selectedWidget !== Settings.leftPanelWidget)
                root.selectedWidget = Settings.leftPanelWidget;
        }
    }
    // Expose the active tab's widget so IPC can poke into the live
    // widget (loadBookmarks/pagedSlice/etc) without traversing the tree.
    // Each branch reads that tab Loader's item, so the binding tracks
    // loads and switches. Unvisited tabs have no item (lazy) — callers
    // already null-check (requestAutoHide/leaveTimer/widgetState).
    readonly property var activeWidget: {
        switch (widgetStack.currentIndex) {
        case 0:
            return aboutLoader.item;
        case 1:
            return chatBotLoader.item;
        case 2:
            return settingsLoader.item;
        case 3:
            return scriptsLoader.item;
        case 4:
            return keybindsLoader.item;
        default:
            return null;
        }
    }

    // Map a tab name (matching the launcher's quick-app selectors) to a widget.
    function selectTab(name) {
        root.selectedWidget = name;
    }

    // Build a tab's Loader without switching to it or opening the island
    // (primes on demand, e.g. floating a dialog from another widget).
    function primeTab(name) {
        if (root._visited[name] !== true) {
            var v = Object.assign({}, root._visited);
            v[name] = true;
            root._visited = v;
        }
    }

    // Hover tracking lives here (stable container — content never swaps
    // under the cursor while open). Leaving arms the close timer; the
    // timer re-checks so a fast flick across still closes.
    HoverHandler {
        id: islandHover
        onHoveredChanged: {
            if (islandHover.hovered) {
                leaveTimer.stop();
                // Pin hover-driven islands so a hold expiry can't close
                // the panel while it is being used.
                BarState.activate("left", 0);
            } else {
                root.requestAutoHide();
            }
        }
    }
    function requestAutoHide() {
        if (Settings.leftPanelLock)
            return;
        if (islandHover.hovered)
            return;
        if (root.activeWidget && root.activeWidget.popupHovered)
            return;
        leaveTimer.restart();
    }
    // Called by the bar owner on every (re)open: the island now survives
    // closes, so a leaveTimer armed before the last close must not fire
    // into the fresh session and shut it after the reveal-out delay
    // with no hover-leave.
    function cancelPendingHide() {
        leaveTimer.stop();
    }
    Timer {
        id: leaveTimer
        interval: Settings.revealOutPressure
        onTriggered: {
            if (!Settings.leftPanelLock && !islandHover.hovered && !(root.activeWidget && root.activeWidget.popupHovered))
                BarState.deactivate("left");
        }
    }

    // Esc dismiss once the surface has focus (click a control first).
    IslandEscClose {
        states: ["left"]
    }

    IslandExpandClip {
        expand: root.expand
        contentHeight: bodyRow.height
        anchors.top: Settings.barOrientation ? parent.top : undefined
        anchors.bottom: Settings.barOrientation ? undefined : parent.bottom

        Row {
            id: bodyRow
            width: parent.width
            height: root.bodyHeight
            spacing: 0

            // Left sidebar with widget selectors
            Rectangle {
                id: sidebar
                width: 48
                height: parent.height
                color: Theme.bg
                radius: Theme.radius
                clip: true

                // Widget selector rail (shared component: tab order,
                // icons and tooltips preserved).
                IslandSideRail {
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.margins: 8
                    // Tab order + icons: About, ChatBot,
                    // Settings, CustomScripts, KeyBinds. Names keep the QS "Widget"
                    // suffix (IPC showWidget/widgetState compat).
                    model: [
                        {
                            name: "About",
                            icon: "\u{f05a}"
                        },
                        {
                            name: "ChatBot",
                            icon: ""
                        },
                        {
                            name: "SettingsWidget",
                            icon: ""
                        },
                        {
                            name: "CustomScripts",
                            icon: ""
                        },
                        {
                            name: "KeyBinds",
                            icon: ""
                        }
                    ]
                    currentIndex: root.tabIndex(root.selectedWidget)
                    onSelected: index => {
                        root.selectedWidget = root.tabOrder[index];
                    }
                }
                // WindowActions: bottom cluster (valign END, shared).
                IslandWindowActions {
                    side: "left"
                    anchors.bottom: parent.bottom
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.margins: 8
                }
            }

            // Main content area
            Item {
                id: contentArea
                width: parent.width - sidebar.width
                height: parent.height

                // Widget stack — each tab is a Loader that activates on first
                // select and stays alive, so tab
                // switches preserve scroll/page/chat state. Only the
                // selected tab instantiates: opening the island builds one
                // widget instead of all five. Only the current one is
                // visible; loaded hidden tabs exist in memory but don't
                // paint. Order matches the tab rail above.
                // Fade-in on switch (opacity-in 0.6s).
                OpacityAnimator on opacity {
                    id: switchAnim
                    from: 0
                    to: 1
                    duration: 600
                    easing.type: Easing.OutCubic
                }
                StackLayout {
                    id: widgetStack
                    anchors.fill: parent
                    anchors.margins: 4
                    currentIndex: {
                        switch (root.selectedWidget) {
                        case "About":
                            return 0;
                        case "ChatBot":
                            return 1;
                        case "SettingsWidget":
                            return 2;
                        case "CustomScripts":
                            return 3;
                        case "KeyBinds":
                            return 4;
                        default:
                            return 0;
                        }
                    }
                    Loader {
                        id: aboutLoader
                        active: root.tabPrimed("About")
                        sourceComponent: aboutComp
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                    }
                    Loader {
                        id: chatBotLoader
                        active: root.tabPrimed("ChatBot")
                        sourceComponent: chatBotComp
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                    }
                    Loader {
                        id: settingsLoader
                        active: root.tabPrimed("SettingsWidget")
                        sourceComponent: settingsComp
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                    }
                    Loader {
                        id: scriptsLoader
                        active: root.tabPrimed("CustomScripts")
                        sourceComponent: scriptsComp
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                    }
                    Loader {
                        id: keybindsLoader
                        active: root.tabPrimed("KeyBinds")
                        sourceComponent: keybindsComp
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                    }
                }
                Component {
                    id: aboutComp
                    // Version check + Update (against your fork) and links.
                    GeneralTab {}
                }
                Component {
                    id: chatBotComp
                    ChatBotWidget {}
                }
                Component {
                    id: settingsComp
                    SettingsWidget {}
                }
                Component {
                    id: scriptsComp
                    CustomScriptsWidget {}
                }
                Component {
                    id: keybindsComp
                    KeyBindsWidget {}
                }
            }
        }
    }
}
