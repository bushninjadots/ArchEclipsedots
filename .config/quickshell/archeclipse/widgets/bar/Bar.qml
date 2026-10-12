import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Io
import qs.theme
import qs.services
import qs.widgets.bar
import qs.widgets.bar.islands
import qs.widgets.bar.pill
import qs.widgets.launcher
import qs.widgets.notifications
import qs.widgets.shared
import qs.widgets.frame

// Port of widgets/bar/Bar.tsx — the floating ArchEclipse bar pill.
PanelWindow {
    id: root

    required property ShellScreen screen
    readonly property string monitorName: {
        const hmon = Hyprland.monitorFor(screen);
        if (hmon && hmon.name)
            return hmon.name;
        // fallback: try to get monitor name from screen
        return screen?.name ?? "unknown";
    }
    // Full monitor height for the side islands (they stretch the whole
    // vertical screen, like the old edge panels did). Must use logical
    // screen.height (DIPs) so fractional display scaling does not blow up
    // the height past the physical window and push panels off-screen.
    readonly property int screenHeight: {
        if (screen && screen.height > 0)
            return screen.height;
        const hmon = Hyprland.monitorFor(screen);
        if (hmon && hmon.height > 0) {
            const scale = (hmon.scale && hmon.scale > 0) ? hmon.scale : 1.0;
            return Math.round(hmon.height / scale);
        }
        return 1080;
    }

    // --- window geometry / layer ---
    // Always a full-width overlay strip (top or bottom edge): side pills
    // are independent overlays beside the main pill, never exclusive
    // zones, so anchors never change.
    anchors {
        left: true
        right: true
        top: Settings.barOrientation
        bottom: !Settings.barOrientation
    }

    // layer-shell keyboard grab while the search island is open
    // (the control island stays OnDemand so typing elsewhere keeps working).
    // Bound to activeStates membership (not resolved state) so the grab
    // releases the same tick deactivate() runs — resolved state lags ~100ms
    // behind (debounceResolve), which kept Exclusive held while a freshly
    // launched app mapped, stealing its focus back to the bar.
    WlrLayershell.keyboardFocus: ("search" in BarState.activeStates) ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.OnDemand
    WlrLayershell.exclusiveZone: Settings.barLock ? root.barHeight + root.floatGap : -1
    color: "transparent"
    aboveWindows: true

    // Click-through everywhere except the pills + edge hot-zones. The
    // window is a full-width, full-height transparent surface — without
    // a mask it eats every click outside the pills.
    mask: Region {
        // Null while the pill is concealed (frame mode keeps the surface up
        // for the band, so a hidden pill must not keep eating clicks).
        item: pill.visible ? pill : null
        // Regions track item geometry even when the item is hidden, so
        // null the item while its pill is closed — otherwise the
        // full-height surface eats clicks across the hidden pill's area.
        Region {
            item: leftPill.visible ? leftPill : null
        }
        Region {
            item: rightPill.visible ? rightPill : null
        }
        Region {
            item: secondaryPill.visible ? secondaryPill : null
        }
        Region {
            item: notifPill.visible ? notifPill : null
        }
        Region {
            item: leftHot
        }
        Region {
            item: rightHot
        }
        // Detached islands: each floating pill is its own input region, so the
        // desktop between them stays clickable (the surface itself is not).
        Region {
            item: (stripRoot.detachedBar && stripRoot.detachedBar.pillLeft.visible) ? stripRoot.detachedBar.pillLeft : null
        }
        Region {
            item: (stripRoot.detachedBar && stripRoot.detachedBar.pillCenter.visible) ? stripRoot.detachedBar.pillCenter : null
        }
        Region {
            item: (stripRoot.detachedBar && stripRoot.detachedBar.pillRight.visible) ? stripRoot.detachedBar.pillRight : null
        }
        Region {
            item: (stripRoot.detachedBar && stripRoot.detachedBar.pillBottom.visible) ? stripRoot.detachedBar.pillBottom : null
        }
        Region {
            item: (stripRoot.detachedBar && stripRoot.detachedBar.pillLeftMid.visible) ? stripRoot.detachedBar.pillLeftMid : null
        }
        Region {
            item: (stripRoot.detachedBar && stripRoot.detachedBar.pillRightMid.visible) ? stripRoot.detachedBar.pillRightMid : null
        }
        Region {
            item: vinyl.visible ? vinyl : null
        }
        // Layout editor (Task 7): while editing, the whole surface is
        // interactive so dashed zones, the tray and drags all receive input.
        Region {
            item: editOverlay.visible ? editOverlay : null
        }
    }

    readonly property int barHeight: 32
    // No-frame attached bars may float off the screen edge.
    readonly property int floatGap: !ShellFrame.enabled && !root.pillStyle && !root.detached ? Settings.barEdgeGap : 0
    // Pill bar style (Settings.barStyle === "pill"): the main pill becomes a
    // floating island — all four corners rounded and inset from the bar edge.
    readonly property bool pillStyle: Settings.barStyle === "pill"
    // Detached islands (islands-only option): the sections break apart into
    // one floating pill each (DetachedBar) and the main pill stops showing the
    // default face. It still surfaces transient islands (search/control/…) so
    // popups keep working.
    readonly property bool detached: Settings.barStyle === "islands" && Settings.barIslandsDetached
    // Transient (non-default) island states still use the centred main pill.
    readonly property bool mainTransient: BarState.state !== "default" && BarState.state !== "recording"

    // ---- islands open where their widget lives ----
    // Which bar widget each transient island belongs to. While the default
    // face is up its widget centres are cached; when an island opens it
    // grows out of that spot (clamped on screen) instead of the bar centre.
    readonly property var islandOwner: ({
        weather: "weather", network: "network", control: "control", volume: "volume",
        brightness: "brightness", player: "media", system: "resources",
        battery: "battery", bluetooth: "bluetooth"
    })
    property var _widgetCentres: ({})
    property var _mediaCell: null
    // Where the vinyl hangs from: under the music widget (its section pill
    // when detached), else the middle of the bar / pill.
    readonly property point vinylAnchor: {
        const top = Settings.barOrientation;
        const m = root._mediaCell;
        if (root.detached && m)
            return Qt.point(m.x, top ? m.bottom + 7 : m.top - 7);
        const x = (!root.pillStyle && m) ? m.x : pill.x + pill.width / 2;
        return Qt.point(x, top ? pill.y + pill.height : pill.y);
    }
    function _cacheWidgetCentres() {
        if (root.mainTransient || BarEditState.active)
            return;
        const surface = root.layoutSurface;
        const cells = surface && typeof surface.editCells === "function" ? surface.editCells() : [];
        if (!cells.length)
            return;
        const m = {};
        let media = null;
        for (const c of cells) {
            m[c.id] = c.x + c.w / 2;
            if (c.id === "media" && c.w > 0)
                media = c;
        }
        root._widgetCentres = m;
        root._mediaCell = media ? { x: media.x + media.w / 2, w: media.w, top: media.y, bottom: media.y + media.h } : null;
    }
    readonly property real islandAnchorX: {
        const id = root.islandOwner[BarState.state];
        const x = id ? root._widgetCentres[id] : undefined;
        return x !== undefined ? x : -1;
    }
    // The face the edit overlay reads geometry from: the detached pills when
    // detached, else the attached default face (currentPageLoader.item).
    readonly property var layoutSurface: root.detached ? stripRoot.detachedBar : currentPageLoader.item
    // Snap the layer surface to content (no Behavior here — animating the
    // PanelWindow renegotiates with the compositor every frame and stutters).
    // Inner content (pill width transition + island expand transition) carries motion.
    // The surface stays full monitor height at all times — never snapped
    // to content. Snapping (38px <-> ~1065px) on every panel open/close
    // reallocates the layer buffer mid-glide, flashing the static main
    // pill and perturbing width measurement for a frame (expand/collapse
    // flicker). Input stays pill-only via the mask; the zone reservation
    // is unchanged (exclusiveZone above). Stretched full-width mode
    // ignores implicit sizes, so this is safe.
    implicitHeight: root.screenHeight
    implicitWidth: pill.width

    // visibility: search pins; override wins;
    // otherwise lock/smart-hide geometric room-check.
    // Re-evaluate when Hyprland geometry events arrive (clients move/resize).
    readonly property bool roomCheckLive: BarState.hyprlandTick >= 0

    readonly property bool barVisible: {
        if (BarEditState.active)
            return true;
        if (BarState.state === "search" || BarState.state === "control" || BarState.state === "overview" || BarState.leftOpen || BarState.rightOpen)
            return true;
        const override = (BarState.barShown || {})[monitorName];
        if (override !== undefined)
            return override;
        BarState.hyprlandTick; // reap the reactive dependency
        return BarState.barVisibleFor(monitorName);
    }

    // --- hover: expand on enter, collapse after leave delay (motion
    // controller on the bar pill; leave arms a 250ms timer that collapses
    // only if the pointer is still off AND no popup is open) ---
    property bool hovered: pillHover.hovered
    // Documentation capture: expose the captured pill, not always the
    // main one — side-pill shots must frame the side pill (and image
    // inspection must walk its tree, not the bar strip's).
    readonly property var captureItem: BarState.leftOpen && leftLoader.item ? leftLoader.item : (BarState.rightOpen && rightLoader.item ? rightLoader.item : pill)
    function captureGeometry() {
        if (BarState.leftOpen)
            return root.sideCaptureGeometry(leftPill, "left");
        if (BarState.rightOpen)
            return root.sideCaptureGeometry(rightPill, "right");
        const p = pill.mapToItem(root.contentItem, 0, 0);
        return {visible: root.visible, displayed: stack.current,
            rect: {x: p.x, y: p.y, w: pill.width, h: pill.height}};
    }
    function sideCaptureGeometry(pillItem, name) {
        const g = pillItem.mapToItem(root.contentItem, 0, 0);
        return {visible: root.visible, displayed: name,
            rect: {x: g.x, y: g.y, w: pillItem.width, h: pillItem.height}};
    }

    // --- live geometry feed for the desktop-widgets aura visualiser ---
    // The aura runs in a separate Quickshell process that cannot see the bar,
    // so publish the main pill and both side-panel inner edges every frame the
    // pills/unfold animate. A closed panel collapses to the screen edge via the
    // clip's expand (0 -> screen edge, 1 -> panel inner edge), which slides the
    // aura's band in lock-step with the panel's own unfold.
    function _auraRect(item) {
        // stripRoot fills contentItem at (0,0), so the item's own x/y are the
        // same coordinates. Reading them directly (unlike mapToItem) makes the
        // Binding re-evaluate when the item slides, not only when it resizes.
        return { x: item.x, y: item.y, w: item.width, h: item.height };
    }

    Binding {
        target: AuraBridge
        property: "pillRect"
        value: root._auraRect(pill)
    }
    Binding {
        target: AuraBridge
        property: "leftRect"
        value: ({
            x: 0,
            y: leftPill.y,
            w: (leftPill.x + leftPill.width) * leftClip.expand,
            h: leftPill.height
        })
    }
    Binding {
        target: AuraBridge
        property: "rightRect"
        value: ({
            x: stripRoot.width - (stripRoot.width - rightPill.x) * rightClip.expand,
            y: rightPill.y,
            w: 0,
            h: rightPill.height
        })
    }
    Binding {
        target: AuraBridge
        property: "pillShown"
        value: root.barVisible
    }
    Binding {
        target: AuraBridge
        property: "barGap"
        value: root.barHeight
    }
    Binding {
        target: AuraBridge
        property: "screenW"
        value: (root.screen && root.screen.width > 0) ? root.screen.width : 1920
    }
    Binding {
        target: AuraBridge
        property: "screenH"
        value: root.screenHeight
    }
    Binding {
        target: AuraBridge
        property: "screenScale"
        value: (root.screen && root.screen.scale) ? root.screen.scale : 1
    }
    // --- bodies for the shell frame (Settings -> Shell frame) ---
    // The main pill and each side panel's visible extent (the unfold clip's
    // live height, grown from the bar edge), so the frame's fillets track the
    // same frame the pills move on.
    function _frameSide(pillItem, clip) {
        const h = clip.height;
        return {
            x: pillItem.x,
            y: Settings.barOrientation ? pillItem.y : pillItem.y + pillItem.height - h,
            w: pillItem.width,
            h: h,
            on: pillItem.visible && h > 1
        };
    }
    readonly property var frameBodies: ({
        pill: { x: pill.x, y: pill.y, w: pill.width, h: pill.height, on: root.barVisible },
        left: root._frameSide(leftPill, leftClip),
        right: root._frameSide(rightPill, rightClip)
    })

    // ---- section-aware frame bodies ----
    // The frame hugs the navbar's SECTIONS, not one blob and not one nub per
    // widget: each section (left / centre capsule / right / bottom row, or a
    // detached section pill) becomes one body grown out of the band, so
    // moving a widget between sections reshapes the frame around it. A widget
    // set to its own shape (Pill / Float) is split out of its section's run
    // and gets its own rounded body; Tab squares the run's far corners.
    // While editing, the drag ghost is a real rendered cell, so the frame
    // follows the drag live.
    function _radiusFor(fit) {
        if (fit.radius >= 0)
            return fit.radius;
        return Theme.radius;
    }

    // Body grown from the bar edge down/up to `r` (its far side rounded).
    function _edgeBody(r, padX, padY, radius) {
        const top = Settings.barOrientation;
        const y0 = top ? 0 : r.y - padY;
        const y1 = top ? r.y + r.h + padY : root.height;
        return { x: r.x - padX, y: y0, w: r.w + padX * 2, h: Math.max(1, y1 - y0), on: true,
                 tl: top ? 0 : radius, tr: top ? 0 : radius,
                 br: top ? radius : 0, bl: top ? radius : 0 };
    }

    // Free body round a rect, every corner rounded.
    function _floatBody(r, gap, radius) {
        return { x: r.x - gap, y: r.y - gap, w: r.w + gap * 2, h: r.h + gap * 2, on: true,
                 tl: radius, tr: radius, br: radius, bl: radius };
    }

    function _bbox(list) {
        let x0 = 1e9, y0 = 1e9, x1 = -1e9, y1 = -1e9;
        for (const c of list) {
            x0 = Math.min(x0, c.x); y0 = Math.min(y0, c.y);
            x1 = Math.max(x1, c.x + c.w); y1 = Math.max(y1, c.y + c.h);
        }
        return { x: x0, y: y0, w: x1 - x0, h: y1 - y0 };
    }

    // Split a section's cells into runs of band-melting widgets and
    // individually-shaped ones. Returns { runs: [[cells]], own: [cells] }.
    function _splitRuns(cells) {
        const runs = [], own = [];
        let cur = [];
        for (const c of cells.slice().sort((a, b) => a.x - b.x)) {
            const shape = BarEditState.frameFor(c.id).shape;
            if (shape === "pill" || shape === "detach") {
                if (cur.length) runs.push(cur);
                cur = [];
                own.push(c);
            } else {
                cur.push(c);
            }
        }
        if (cur.length) runs.push(cur);
        return { runs: runs, own: own };
    }

    function _ownBody(c) {
        const fit = BarEditState.frameFor(c.id);
        const gap = fit.shape === "detach" ? 6 : 3;
        return root._floatBody(c, gap, root._radiusFor(fit));
    }

    function _runRadius(run) {
        let square = true, r = -1;
        for (const c of run) {
            const fit = BarEditState.frameFor(c.id);
            if (fit.shape !== "square") square = false;
            if (fit.radius >= 0) r = Math.max(r, fit.radius);
        }
        return square ? 0 : (r >= 0 ? r : Theme.radius);
    }

    // Seat a body against the screen: within reach of a side or edge it is
    // extended flush into the band there and its corners on that side go
    // square, so a section next to the frame's side (or a corner) reads as
    // one piece with it instead of a pinched neck beside the band's own
    // rounded corner. A body touching the band keeps the shared fillet; a
    // floating one gets none (fuse 0), so it never sprouts a bridge.
    function _seat(b) {
        const W = root.width, H = root.height;
        const reach = ShellFrame.band + ShellFrame.fuse + 2;
        if (b.x <= reach && b.x > -1) {
            b.w += b.x;
            b.x = 0;
            b.tl = 0;
            b.bl = 0;
        }
        if (W - (b.x + b.w) <= reach && b.x + b.w < W + 1) {
            b.w = W - b.x;
            b.tr = 0;
            b.br = 0;
        }
        if (b.y <= reach && b.y > 0) {
            b.h += b.y;
            b.y = 0;
            b.tl = 0;
            b.tr = 0;
        }
        if (H - (b.y + b.h) <= reach && b.y + b.h < H) {
            b.h = H - b.y;
            b.bl = 0;
            b.br = 0;
        }
        const touches = b.x <= 0 || b.y <= 0 || b.x + b.w >= W || b.y + b.h >= H;
        if (b.fuse === undefined)
            b.fuse = touches ? ShellFrame.fuse : 0;
        return b;
    }

    function _computeFrameBodiesList() {
        const out = [];
        const b = root.frameBodies;
        // Every body carries a stable key so FrameField can morph it.
        const add = (body, key) => {
            if (body && body.on !== false && body.w > 0 && body.h > 0) {
                body.key = key;
                // The pill style's island and Float/Pill widget bodies are
                // meant to hover: they keep their gap (pill keeps its melt).
                const floating = key.startsWith("own:") || (key === "pill" && root.pillStyle);
                if (floating && body.fuse === undefined)
                    body.fuse = key === "pill" ? ShellFrame.fuse : 0;
                out.push(floating ? body : root._seat(body));
            }
        };
        const surface = root.layoutSurface;
        const sections = surface && typeof surface.frameSections === "function" ? surface.frameSections() : [];
        const cells = surface && typeof surface.editCells === "function" ? surface.editCells() : [];
        const byZone = {};
        for (const c of cells)
            (byZone[c.zone] = byZone[c.zone] || []).push(c);

        if (root.pillStyle || (!root.detached && (root.mainTransient || sections.length === 0))) {
            // Pill style, a transient island, or nothing placed: the whole
            // main pill is the body (the original frame).
            add(Object.assign({}, b.pill), "pill");
        } else if (root.detached) {
            // Detached: each section pill is its own floating body; shaped
            // widgets inside add their own outline.
            for (const sec of sections) {
                add(root._floatBody(sec, 0, Theme.radius), "sec:" + sec.zone);
                for (const c of root._splitRuns(byZone[sec.zone] || []).own)
                    add(root._ownBody(c), "own:" + c.id);
            }
            if (root.mainTransient)
                add(Object.assign({}, b.pill), "pill");
        } else {
            // Attached islands: section runs grow out of the band.
            for (const sec of sections) {
                const split = root._splitRuns(byZone[sec.zone] || []);
                const whole = split.own.length === 0 && split.runs.length === 1;
                for (const run of split.runs) {
                    // An unsplit section uses its own rect (the centre capsule
                    // keeps its padding); split runs hug their widgets.
                    const r = whole ? sec : root._bbox(run);
                    add(root._edgeBody(r, whole ? 6 : 8, 5, root._runRadius(run)),
                        whole ? "sec:" + sec.zone : "run:" + sec.zone + ":" + run[0].id);
                }
                for (const c of split.own)
                    add(root._ownBody(c), "own:" + c.id);
            }
        }
        add(Object.assign({}, b.left), "side-left");
        add(Object.assign({}, b.right), "side-right");
        return out;
    }

    // Sample body geometry every rendered frame while the shell frame is
    // enabled. QML cannot reliably observe x/y changes behind dynamically
    // returned editCells() arrays, so this explicit dependency keeps the
    // shader's body outlines glued to animated/moving navbar sections.
    property int frameGeometryTick: 0
    FrameAnimation {
        running: ShellFrame.enabled
        onTriggered: root.frameGeometryTick++
    }
    // Keep the widget-centre cache fresh (cheap; only while the default face shows).
    Timer {
        interval: 400
        repeat: true
        running: root.barVisible && !root.mainTransient
        triggeredOnStart: true
        onTriggered: root._cacheWidgetCentres()
    }
    readonly property var frameBodiesList: {
        root.frameGeometryTick;
        return root._computeFrameBodiesList();
    }

    // Instantiates the (lazy) window-border colour follower.
    readonly property bool _windowBorderFollows: WindowBorder.active

    Component.onDestruction: Registry.unregister("capture-bar-" + root.monitorName)
    Component.onCompleted: {
        Registry.register("capture-bar-" + root.monitorName, root);
        if (Settings.barDefault)
            BarState.activate("default");
    }
    onHoveredChanged: {
        if (hovered) {
            BarState.activate("default");
            hideTimer.stop();
        } else {
            hideTimer.restart();
        }
    }

    Timer {
        id: hideTimer
        interval: 250
        onTriggered: {
            // Leave handler: collapse default (guarded by hover+popup),
            // then conceal the bar when unlocked and search isn't pinning it.
            if (!root.hovered && BarState.popupCount <= 0 && !Settings.barDefault)
                BarState.deactivate("default");
            if (BarState.state !== "search" && BarState.state !== "control" && BarState.state !== "overview" && !BarState.leftOpen && !BarState.rightOpen && !Settings.barLock && !root.hovered && BarState.popupCount <= 0)
                BarState.concealBar(root.monitorName);
        }
    }

    // idle watchdog for hover-reveal overrides
    Connections {
        target: BarState
        function onBarShownChanged() {
            if (BarState.barShown[root.monitorName] === true)
                idleTimer.restart();
            else
                idleTimer.stop();
        }
    }
    Timer {
        id: idleTimer
        interval: 1500
        running: (BarState.barShown || {})[root.monitorName] === true
        onTriggered: {
            if (Settings.barLock)
                return;
            if (BarState.state === "search" || BarState.state === "control" || BarState.state === "overview" || BarState.leftOpen || BarState.rightOpen) {
                idleTimer.restart();
                return;
            }
            // Watchdog: don't trust the hover read alone (reveals
            // can fire without an enter/leave cycle). Ask Hyprland where the
            // cursor actually is; if it is over the bar band or a popup is
            // open, keep waiting. If position is unknown, DON'T conceal
            // blindly — restart the check.
            if (BarState.popupCount > 0) {
                idleTimer.restart();
                return;
            }
            root.verifyCursorOffBar();
        }
    }

    // pointerOnBar(): cursorpos vs monitor band geometry.
    property var _cursorProc: null
    function verifyCursorOffBar() {
        if (root._cursorProc)
            return;
        var p = Qt.createQmlObject('import Quickshell.Io; Process { command: ["hyprctl", "cursorpos"] }', root);
        root._cursorProc = p;
        var out = Qt.createQmlObject('import Quickshell.Io; StdioCollector {}', root);
        p.stdout = out;
        out.onStreamFinished.connect(() => {
            var proc = root._cursorProc;
            root._cursorProc = null;
            var stillOff = root.cursorOffBar(out.text);
            if (stillOff === true) {
                if (!root.hovered && BarState.popupCount <= 0)
                    BarState.concealBar(root.monitorName);
            } else if (stillOff === false) {
                idleTimer.restart();
            } else {
                // unknown — don't conceal blindly
                idleTimer.restart();
            }
            out.destroy();
            proc.destroy();
        });
        p.running = true;
    }
    // Returns true = cursor verifiably off bar, false = on bar,
    // undefined = can't tell.
    function cursorOffBar(cursorText) {
        try {
            var parts = (cursorText || "").trim().split(",");
            if (parts.length < 2)
                return undefined;
            var x = parseInt(parts[0], 10);
            var y = parseInt(parts[1], 10);
            if (isNaN(x) || isNaN(y))
                return undefined;
            var mon = Hyprland.monitorFor(screen);
            if (!mon)
                return undefined;
            var h = root.barHeight;
            var monW = (screen && screen.width > 0) ? screen.width : ((mon.width > 0 && mon.scale > 0) ? Math.round(mon.width / mon.scale) : mon.width);
            var monH = root.screenHeight;
            var monX = (mon.scale && mon.scale > 0) ? Math.round(mon.x / mon.scale) : mon.x;
            var monY = (mon.scale && mon.scale > 0) ? Math.round(mon.y / mon.scale) : mon.y;
            if (x < monX || x > monX + monW)
                return true;
            var onBar = Settings.barOrientation ? y <= monY + h : y >= monY + monH - h;
            return !onBar;
        } catch (e) {
            return undefined;
        }
    }

    Item {
        id: stripRoot
        anchors.fill: parent

        // ---- editor focus scrim ----
        // While the layout editor is open everything behind the bar dims, so
        // the bar (and the editor sheet) is what you look at.
        Rectangle {
            anchors.fill: parent
            color: "black"
            opacity: BarEditState.active ? 0.42 : 0
            visible: opacity > 0.01
            Behavior on opacity {
                NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
            }
        }

        // ---- the shell frame (Settings -> Bar -> Shell Style "Frame") ----
        // Part of the bar's own surface, under every pill: the band borders
        // the screen and the pills grow out of it in the same frame they move.
        FrameField {
            id: frameField
            anchors.fill: parent
            bodies: root.frameBodies
            bodiesList: root.frameBodiesList
            topBar: Settings.barOrientation
            // The music lifts the band under the bar's own span.
            pullX: pill.x + pill.width / 2
            pullHalf: pill.width / 2
        }

        // Half-cut vinyl under the music widget (Settings -> Bar -> Music).
        // Before the pill so it reads as sliding out from under the bar.
        BarVinyl {
            id: vinyl
            anchorX: root.vinylAnchor.x
            anchorY: root.vinylAnchor.y
            allowed: root.barVisible && !root.mainTransient && !BarEditState.active
            // Pill style spans the pill; islands span the music widget plus
            // its pill padding.
            matchWidth: root.pillStyle || !root._mediaCell ? pill.width - 16 : root._mediaCell.w + 14
        }

        // No-frame surface for the main pill (Settings -> Bar -> Surface).
        BarSurface {
            x: pill.x
            y: pill.y
            width: pill.width
            height: pill.height
            visible: pill.visible && !ShellFrame.enabled && Settings.barSurfaceStyle !== "clear"
            topLeftRadius: pill.topLeftRadius
            topRightRadius: pill.topRightRadius
            bottomLeftRadius: pill.bottomLeftRadius
            bottomRightRadius: pill.bottomRightRadius
            live: root.mainTransient
        }

        // ---- the pill ----
        Rectangle {
            id: pill
            // In frame mode the surface stays up for the band, so the pill
            // conceals itself; otherwise the window's own visibility does it.
            // Detached: the default face lives in DetachedBar, so the main
            // pill only appears for transient islands (search/control/…).
            visible: root.detached
                ? (root.barVisible && root.mainTransient)
                : (!ShellFrame.enabled || root.barVisible)
            // Pushed-center: side pills dock to the screen edges and the
            // main pill centers in the remaining space — never fixed-center,
            // never overlapping. `x` itself carries NO Behavior: it tracks
            // per-frame (rigidly coupled to width animations). Discrete
            // open/close pushes animate through leftPush/rightPush with the
            // same easing as the width, so everything moves as one unit.
            property real leftPush: leftPill.flag ? 8 + leftPill.width + 8 : 0
            Behavior on leftPush {
                Anim {
                    type: Anim.DefaultSpatial
                }
            }
            property real rightPush: (rightPill.flag ? rightPill.width + 8 : 0) + (secondaryPill.flag ? secondaryPill.width + 8 : 0)
            Behavior on rightPush {
                Anim {
                    type: Anim.DefaultSpatial
                }
            }
            property real pillX: {
                var rightStart = rightPush > 0 ? parent.width - 8 - rightPush : parent.width;
                return leftPush + Math.max(0, (rightStart - leftPush - pill.width) / 2);
            }
            // Offset from the centred slot toward the owning widget (eased,
            // so the island glides out of the widget rather than jumping).
            property real anchorShift: {
                if (!root.mainTransient || root.islandAnchorX < 0)
                    return 0;
                const want = root.islandAnchorX - pill.width / 2;
                const lo = leftPush + 8, hi = parent.width - pill.width - 8 - (rightPush > 0 ? rightPush + 8 : 0);
                return Math.max(lo, Math.min(hi, want)) - pillX;
            }
            Behavior on anchorShift {
                Anim {
                    type: Anim.DefaultSpatial
                }
            }
            x: pillX + anchorShift
            // Detached islands: a transient island drops down under the
            // section pills (a popover from its widget) instead of covering
            // them; otherwise it sits on the bar edge as before.
            readonly property real edgeGap: root.detached ? 6 + Theme.barContentHeight + 14 + 8 : (root.pillStyle ? 6 : root.floatGap)
            y: Settings.barOrientation ? pill.edgeGap : parent.height - height - pill.edgeGap
            // Grows with content: 32 for normal states, tall when the
            // search island (input + launcher) is shown.
            height: Math.max(root.barHeight, stack.height + 10)
            // Shrink-only glide: when the target sits below the current
            // height (closes), ease down; when growing, track the unfolding
            // content rigidly per-frame — gliding there would chase a moving
            // target and lag behind it (verified via probe).
            Behavior on height {
                enabled: pill.height > stack.height + 10
                Anim {
                    type: Anim.DefaultSpatial
                }
            }
            // Bound to targetWidth + transition: a plain NumberAnimation
            // (duration + easing curve, no bounce/velocity) keeps state
            // changes predictable — the pill eases between widths instead
            // of overshooting.
            width: targetWidth
            property bool widthAnimReady: false
            Component.onCompleted: widthAnimReady = true
            Behavior on width {
                enabled: pill.widthAnimReady
                Anim {
                    type: Anim.DefaultSpatial
                }
            }
            // Square on the screen-edge side unless it floats (pill style,
            // or a no-frame bar given an edge gap).
            readonly property bool floating: root.pillStyle || root.floatGap > 0
            bottomRightRadius: (Settings.barOrientation || pill.floating) ? Theme.radius : 0
            bottomLeftRadius: (Settings.barOrientation || pill.floating) ? Theme.radius : 0
            topRightRadius: (!Settings.barOrientation || pill.floating) ? Theme.radius : 0
            topLeftRadius: (!Settings.barOrientation || pill.floating) ? Theme.radius : 0
            // Frame mode: FrameField paints this body as part of the frame.
            // No frame: BarSurface (behind the pill, so its shadow isn't
            // clipped) paints it.
            color: "transparent"

            // Hover detection lives on the pill itself (stable container).
            // The motion controller is on the bar pill — hot-zone
            // strips at the bar ends must NOT trigger expand.
            HoverHandler {
                id: pillHover
            }

            // Width target: follows the stack content (one-beat transitions —
            // content swaps immediately while the width glides; the island's
            // own clip wipe masks the grow, and `clip` below cuts spill at
            // the animating edge, so no grow-first pin is needed).
            property real targetWidth: Math.max(stack.width + 10, 100)
            // Cut content wider than the (still gliding) pill at the pill
            // edge: opens reveal outward as the pill grows instead of
            // spilling past it. Settled content fits with 5px to spare,
            // so this is a no-op outside transitions.
            clip: true

            // Music-reactive spectrum behind the content — rises from the
            // pill's inner edge while a track plays (see PillSpectrum.qml).
            // Pill-only and a no-op unless playback is live.
            PillSpectrum {
                anchors.fill: parent
            }

            // ---- state stack (one beat) ----
            // Content swaps the same frame the state resolves; the pill
            // width glides under it while the island unfolds — background
            // and content animate as one unit, like the side pills.
            Item {
                id: stack
                // Docked to the bar edge (top for a top bar, bottom for a
                // bottom bar) — never centered: centering lets content drift
                // vertically while the pill height glides. 5px edge margin
                // preserves the settled 10px surround exactly.
                anchors.top: Settings.barOrientation ? parent.top : undefined
                anchors.bottom: Settings.barOrientation ? undefined : parent.bottom
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.topMargin: 5
                anchors.bottomMargin: 5

                // Size from implicit* only — never .height/.width/childrenRect.
                // Those depend on stack's assigned size and create binding loops.
                property real activeWidth: {
                    var it = currentPageLoader.item;
                    return it ? (it.implicitWidth || 0) : 0;
                }

                onActiveWidthChanged: {
                    if (activeWidth > 0) {
                        stack.width = activeWidth;
                    }
                }

                property real activeHeight: {
                    var hit = currentPageLoader.item;
                    return hit ? (hit.implicitHeight || 0) : 0;
                }

                onActiveHeightChanged: {
                    if (activeHeight > 0) {
                        stack.height = activeHeight;
                    }
                }

                // The state actually shown — bound straight to BarState.state.
                // (A Connections-guarded variant was tried and removed: the
                // binding updates before signal handlers run, so any
                // s === displayed guard exits early forever and branch logic
                // placed there silently never executes — root-caused via
                // probe 2026-09-24. All swap logic lives in onCurrentChanged
                // + bindings below.)
                property string displayed: BarEditState.active ? "default" : BarState.state

                // The live item for a shown state (transient islands via
                // currentPageLoader).

                property string current: stack.displayed
                // Note: volume/brightness/control all resolve to controlPage
                // in the switch below, so pulses across them keep the same
                // Loader item with no swap churn — same content, no reveal.
                // (Recording maps to defaultPage for the same reason.)
                readonly property string previous: ""

                Loader {
                    id: currentPageLoader
                    // Handles the small transient states only — left/right
                    // live in their own side pills, recording in its own.
                    sourceComponent: {
                        switch (stack.current) {
                        case "default":
                            return defaultPage;
                        case "volume":
                            return controlPage;
                        case "brightness":
                            return controlPage;
                        case "recording":
                            // Recording lives in the secondary pill beside
                            // the main pill — the main stack shows default
                            // content so the bar is never hijacked.
                            return defaultPage;
                        case "player":
                            return playerPage;
                        case "weather":
                            return weatherPage;
                        case "network":
                            return networkPage;
                        case "bluetooth":
                            return bluetoothPage;
                        case "battery":
                            return batteryPage;
                        case "search":
                            return searchPage;
                        case "system":
                            return systemPage;
                        case "control":
                            return controlPage;
                        case "overview":
                            return overviewPage;
                        default:
                            return defaultPage;
                        }
                    }
                    // Probe pass-through for per-state bodies.
                    onLoaded: {
                        if (item && item["monitorName"] !== undefined)
                            item.monitorName = root.monitorName;
                        if (item && item["screenHeight"] !== undefined)
                            item.screenHeight = root.screenHeight;
                    }
                }

                Component {
                    id: defaultPage
                    DefaultBar {}
                }
                Component {
                    id: playerPage
                    MprisIsland {}
                }
                Component {
                    id: weatherPage
                    WeatherIsland {}
                }
                Component {
                    id: networkPage
                    NetworkIsland {}
                }
                Component {
                    id: bluetoothPage
                    BluetoothIsland {}
                }
                Component {
                    id: batteryPage
                    BatteryIsland {}
                }
                Component {
                    id: searchPage
                    SearchIsland {}
                }
                Component {
                    id: systemPage
                    SystemMonitorIsland {}
                }
                Component {
                    id: controlPage
                    ControlIsland {}
                }
                Component {
                    id: overviewPage
                    OverviewIsland {}
                }
            }
        }

        // ---- detached islands (Task 8) ----
        // One floating pill per section, rendered only while detached. The
        // edit overlay reads its geometry instead of the attached face's.
        Loader {
            id: detachedLoader
            anchors.fill: parent
            active: root.detached
            sourceComponent: detachedComponent
        }
        Component {
            id: detachedComponent
            DetachedBar {}
        }
        readonly property var detachedBar: detachedLoader.item

        Component {
            id: leftPage
            LeftIsland {
                screenHeight: root.screenHeight
                monitorName: root.monitorName
                screen: root.screen
            }
        }
        Component {
            id: rightPage
            RightIsland {
                screenHeight: root.screenHeight
                monitorName: root.monitorName
            }
        }

        // ---- left side pill (independent of the main pill) ----
        // Owns the left island in a forever-alive cached Loader: created
        // lazily on first open, then visibility-toggled so tab/scroll/
        // chat state survives closes.
        Item {
            id: leftPill
            // Docked to the left screen edge, outermost; the main pill yields.
            // Transparent positioning shell — the surface background lives
            // inside the unfold clip below so the panel wipes as one unit.
            x: 8
            y: Settings.barOrientation ? 0 : parent.height - height
            width: Settings.leftPanelWidth
            height: Math.max(400, root.screenHeight - 15)
            visible: leftPill.shown && root.barVisible
            property bool primed: false
            // Open/close transition (mirrors the main-stack exit driver):
            // open shows instantly and the clip unfolds; close folds first
            // (openT 1 -> 0, animated inside IslandExpandClip) and hides
            // when the fold completes. Reopen mid-fold cancels the hide.
            // openT is set discretely — the clip animates it internally
            // (never chase it with a second Behavior). The island's own
            // expand stays pinned at 1 after creation (dormant): a single
            // unfold plays, exactly like a main-stack island.
            property bool shown: false
            property bool flag: BarState.leftOpen
            onFlagChanged: leftPill.setShown(leftPill.flag)
            Component.onCompleted: leftPill.setShown(leftPill.flag)
            property real openT: 0
            function setShown(open) {
                if (open) {
                    leftCloseTimer.stop();
                    if (!primed)
                        primed = true;
                    else if (leftLoader.item && leftLoader.item["cancelPendingHide"] !== undefined)
                        leftLoader.item.cancelPendingHide();
                    shown = true;
                    openT = 1;
                } else {
                    if (!shown)
                        return;
                    openT = 0;
                    leftCloseTimer.restart();
                }
            }
            Timer {
                id: leftCloseTimer
                interval: Theme.anim.normal
                onTriggered: leftPill.shown = false
            }
            IslandExpandClip {
                id: leftClip
                expand: leftPill.openT
                contentHeight: leftPill.height
                anchors.top: Settings.barOrientation ? parent.top : undefined
                anchors.bottom: Settings.barOrientation ? undefined : parent.bottom
                Rectangle {
                    // In frame mode FrameField paints this body as part of the frame.
                    color: ShellFrame.enabled ? "transparent" : Theme.surface
                    width: parent.width
                    height: leftPill.height
                    anchors.top: Settings.barOrientation ? parent.top : undefined
                    anchors.bottom: Settings.barOrientation ? undefined : parent.bottom
                    bottomRightRadius: Settings.barOrientation ? Theme.radius : 0
                    bottomLeftRadius: Settings.barOrientation ? Theme.radius : 0
                    topRightRadius: Settings.barOrientation ? 0 : Theme.radius
                    topLeftRadius: Settings.barOrientation ? 0 : Theme.radius
                    Loader {
                        id: leftLoader
                        anchors.fill: parent
                        active: leftPill.primed
                        visible: leftPill.visible
                        asynchronous: false
                        sourceComponent: leftPage
                        onLoaded: {
                            if (item && item["monitorName"] !== undefined)
                                item.monitorName = root.monitorName;
                            if (item && item["screenHeight"] !== undefined)
                                item.screenHeight = root.screenHeight;
                            if (item && item["screen"] !== undefined)
                                item.screen = root.screen;
                        }
                    }
                }
            }
        }

        // ---- right side pill (independent of the main pill) ----
        Item {
            id: rightPill
            // Docked to the right screen edge, outermost; the main pill
            // and recording yield. Transparent shell — background lives
            // inside the unfold clip, like leftPill.
            x: parent.width - width - 8
            y: Settings.barOrientation ? 0 : parent.height - height
            width: Settings.rightPanelWidth
            height: Math.max(400, root.screenHeight - 15)
            visible: rightPill.shown && root.barVisible
            property bool primed: false
            // Open/close transition, same pattern as leftPill above.
            property bool shown: false
            property bool flag: BarState.rightOpen
            onFlagChanged: rightPill.setShown(rightPill.flag)
            Component.onCompleted: rightPill.setShown(rightPill.flag)
            property real openT: 0
            function setShown(open) {
                if (open) {
                    rightCloseTimer.stop();
                    if (!primed)
                        primed = true;
                    else if (rightLoader.item && rightLoader.item["cancelPendingHide"] !== undefined)
                        rightLoader.item.cancelPendingHide();
                    shown = true;
                    openT = 1;
                } else {
                    if (!shown)
                        return;
                    openT = 0;
                    rightCloseTimer.restart();
                }
            }
            Timer {
                id: rightCloseTimer
                interval: Theme.anim.normal
                onTriggered: rightPill.shown = false
            }
            IslandExpandClip {
                id: rightClip
                expand: rightPill.openT
                contentHeight: rightPill.height
                anchors.top: Settings.barOrientation ? parent.top : undefined
                anchors.bottom: Settings.barOrientation ? undefined : parent.bottom
                Rectangle {
                    // In frame mode FrameField paints this body as part of the frame.
                    color: ShellFrame.enabled ? "transparent" : Theme.surface
                    width: parent.width
                    height: rightPill.height
                    anchors.top: Settings.barOrientation ? parent.top : undefined
                    anchors.bottom: Settings.barOrientation ? undefined : parent.bottom
                    bottomRightRadius: Settings.barOrientation ? Theme.radius : 0
                    bottomLeftRadius: Settings.barOrientation ? Theme.radius : 0
                    topRightRadius: Settings.barOrientation ? 0 : Theme.radius
                    topLeftRadius: Settings.barOrientation ? 0 : Theme.radius
                    Loader {
                        id: rightLoader
                        anchors.fill: parent
                        active: rightPill.primed
                        visible: rightPill.visible
                        asynchronous: false
                        sourceComponent: rightPage
                        onLoaded: {
                            if (item && item["monitorName"] !== undefined)
                                item.monitorName = root.monitorName;
                            if (item && item["screenHeight"] !== undefined)
                                item.screenHeight = root.screenHeight;
                        }
                    }
                }
            }
        }

        // ---- secondary pill (recording) ----
        // Chained right of the main pill; the right pill sits outermost
        // after it. Owns the recording island so ScreenRecorder never
        // hijacks the main pill: visible only while recording, hidden
        // with the bar (fullscreen/conceal).
        Item {
            id: secondaryPill
            // Rigid chain right of the main pill (no Behavior — tracks
            // per-frame, coupled to the main pill's own motion).
            // Transparent shell — background wipes inside the clip.
            x: pill.x + pill.width + 8
            y: Settings.barOrientation ? 0 : parent.height - height
            height: root.barHeight
            width: secondaryLoader.item ? (secondaryLoader.item.implicitWidth + 10) : 190
            visible: secondaryPill.shown && root.barVisible
            // Open/close transition: the clip unfolds; the Loader
            // deactivates after the fold. Reopen mid-fold cancels the
            // hide. openT is discrete — the clip animates it internally.
            property bool shown: false
            property bool flag: ScreenRecorder.isRecording
            onFlagChanged: secondaryPill.setShown(secondaryPill.flag)
            Component.onCompleted: secondaryPill.setShown(secondaryPill.flag)
            property real openT: 0
            function setShown(open) {
                if (open) {
                    recCloseTimer.stop();
                    shown = true;
                    openT = 1;
                } else {
                    if (!shown)
                        return;
                    openT = 0;
                    recCloseTimer.restart();
                }
            }
            Timer {
                id: recCloseTimer
                interval: Theme.anim.normal
                onTriggered: secondaryPill.shown = false
            }

            IslandExpandClip {
                expand: secondaryPill.openT
                contentHeight: secondaryPill.height
                anchors.top: parent.top
                Item {
                    width: parent.width
                    height: secondaryPill.height
                    Loader {
                        id: secondaryLoader
                        anchors.centerIn: parent
                        active: secondaryPill.shown
                        sourceComponent: secondaryRecordingPage
                    }
                }
            }
            Component {
                id: secondaryRecordingPage
                RecordingIsland {}
            }
        }

        // ---- notification pill (centered below the main pill) ----
        // Owns the toast stack so popups never need a separate window.
        // Stays clickable/mapped on toasts alone: the window visible flag
        // below ORs barVisible with notifPill.hasContent.
        NotificationPopups {
            id: notifPill
            pillX: pill.x
            pillY: pill.y
            pillW: pill.width
            pillH: pill.height
            topBar: Settings.barOrientation
        }

        // ---- hot zones (left/right island reveal strips) ----
        HotZone {
            id: leftHot
            side: "left"
            size: Settings.leftPanelHotZoneSize
            enabled: Settings.leftPanelHotZone
            panelLock: Settings.leftPanelLock
        }
        HotZone {
            id: rightHot
            side: "right"
            size: Settings.rightPanelHotZoneSize
            enabled: Settings.rightPanelHotZone
            panelLock: Settings.rightPanelLock
        }

        // ---- layout editor (Task 7) ----
        BarEditOverlay {
            id: editOverlay
            anchors.fill: parent
            // Detached mode publishes geometry from the floating pills.
            source: root.layoutSurface
        }
    }

    // The toast pill maps on toasts alone so notifications survive a
    // concealed bar (the old separate window always did).
    visible: barVisible || notifPill.hasContent || ShellFrame.enabled
}
