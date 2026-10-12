# Bar Editing UX Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make editing both bar styles (pill + islands) direct and predictable, make the Settings bar controls clearer, and make moving components compose with the shell frame instead of fighting it.

**Architecture:** Edit mode becomes a first-class bar state. `BarEditState` holds a transient undo snapshot, a live-reorder preview, and entry/exit APIs; `services/Ipc.qml` exposes `bar edit` / `bar editCancel` / `bar editDone`; `Bar.qml` owns the hover entry affordance and adds the dragged component's frame body; `BarEditOverlay.qml` owns the new header chrome, the drag-only tray shelf, the real-widget drag proxy, and Esc. Bar faces (`DefaultBar`, `PillBar`, `DetachedPill`) render the preview sequence and animate reorders. Settings gains one persisted toggle (`bar.edit.frameFollowsDrag`). Pass 2 reorganizes the Settings Bar card into Bar / Layout / Frame sub-cards.

**Tech Stack:** QML (Qt 6, Quickshell), QtQuick positioners, `ShaderEffect` shell frame (`widgets/frame/FrameField.qml` + `frame.frag`), JSON settings via `theme/Settings.qml`, Hyprland + `qs` IPC.

**Spec:** `docs/superpowers/specs/2026-10-12-bar-editing-ux-design.md`

## Global Constraints

- Do **not** change `widgets/frame/frame.frag` or `frame.frag.qsb`, and do **not** change the fixed-slot individual-uniform body mechanism (the previous fix stays).
- Do not add widget types or change widget internals.
- Do not change the persisted layout schema except adding the single optional key `bar.edit.frameFollowsDrag` (bool, default `true`).
- All persistent writes go through `Settings.updateSetting(path, value)` (keeps memory + `settings.json` in lock-step). No direct file writes.
- New/changed QML must follow existing style: 4-space indent, `readonly property` for derived values, functions for logic, `Anim`/`CAnim` from `qs.widgets.shared` for animations.
- Do **not** commit unless the user asks. Stage only the files this plan touches.
- `bar.sh` does a `pkill -f` that matches any process whose command line contains `quickshell`; always invoke it from a script file, never inline.
- Reload command: `bash ~/.config/hypr/scripts/bar.sh`. Config path for IPC: `/home/bender/.config/quickshell/archeclipse`.
- `qmllint <files>` is the static gate. In this repo the `qs.*` imports are not resolvable, so `qmllint` exits 255 with no output for files that import them — that is the environment baseline PASS; any other nonzero exit or output is a failure.
- Log to grep: `/tmp/qs-bar-$USER.log`; failure pattern `typeerror|referenceerror|binding loop|Error` (case-insensitive).

## Review Focus

Inputs/conditions the spec implies but does not specify; each must not break:

1. **Bar concealed / not hovered** — the entry grip must not appear, and entering via IPC/Settings must still work when the bar is hidden.
2. **Frame disabled** (`Settings.shellFrame === false`) — edit mode must not reference frame bodies; no dragged body is drawn; no error.
3. **Cross-edge + tray drops during a live drag** — dragging a widget to the other edge, to an edge that disallows it, or off the bar entirely must leave the model consistent (no duplicated/lost id).
4. **Empty edge / single widget** — a strip with zero or one placed widget must lay out and drop without divide-by-zero or NaN geometry.
5. **Reset then Cancel** — after `Reset default`, Cancel must still restore the layout captured on entry (not the code defaults).

---

## File Structure

- `services/BarEditState.qml` — **modify**: undo snapshot + `cancel()`; transient live-reorder preview (`previewOrder`, `previewSequence(style, edge)`); helper `draggedBodyRect()` for the frame.
- `services/Ipc.qml` — **modify**: `edit`, `editCancel`, `editDone`, `editDiag` on the `bar` IpcHandler.
- `theme/Settings.qml` — **modify**: `barFrameFollowsDrag` property, alias, persistence read/write.
- `widgets/bar/BarEditOverlay.qml` — **modify**: header chrome (style label + hint + `Frame follows drag` toggle + Save/Cancel/Reset), drag-only tray shelf, real-widget proxy, Esc.
- `widgets/bar/EditStrip.qml` — **create**: one horizontal sequence strip (ListModel + horizontal `ListView` with a `move` transition) so live reorders animate instead of rebuilding.
- `widgets/bar/DefaultBar.qml` — **modify**: top/bottom edges render `EditStrip`; consume `previewSequence`.
- `widgets/bar/pill/PillBar.qml` — **modify**: track becomes an `EditStrip`; consumes `previewSequence`.
- `widgets/bar/DetachedPill.qml` — **modify**: per-widget lift/grab affordance; section drag unchanged behaviour.
- `widgets/bar/Bar.qml` — **modify**: hover entry grip; dragged-component frame body (`_computeFrameBodiesList`); pass through.
- `widgets/leftPanel/SettingsWidget.qml` — **modify (Pass 2)**: Bar / Layout / Frame sub-cards.

---

## Task 1: Edit entry/exit IPC + undo snapshot

**Files:**
- Modify: `services/BarEditState.qml`
- Modify: `services/Ipc.qml` (IpcHandler `target: "bar"`, after `barDiag`)
- Test: CLI probe via `qs ... ipc call bar`

**Interfaces:**
- Produces (BarEditState):
  - `readonly property bool canCancel: bool` — true while an undo snapshot is held.
  - `function cancel(): void` — restore the entry snapshot, then clear it and deactivate (same cleanup as `end()`).
  - `property var previewOrder: ({})` — empty for now; filled in Task 5.
  - `function previewSequence(style: string, edge: string) -> var` — for now returns `BarWidgets.layoutLinear(style, edge)`.
  - `begin(style)` captures the snapshot; `end()` clears the snapshot.
- Produces (IpcHandler `bar`):
  - `function edit(mode: string): string` — `mode` "" | "islands" | "pill". Toggles: if `BarEditState.active` → `end()` and return `"editing off"`; else `begin(mode || Settings.barStyle)` and return `"editing " + BarEditState.style`.
  - `function editCancel(): string` → `"cancelled"`.
  - `function editDone(): string` → `"done"`.
  - `function editDiag(query: string): string` — QA probe; supports `"active"`, `"style"`, `"canCancel"`, `"reset"` (calls `BarEditState.resetLayout()`); returns `"unknown query"` otherwise (more queries added in later tasks).

- [ ] **Step 1: Write the failing probe check**

Run:
```bash
qs -p /home/bender/.config/quickshell/archeclipse ipc call bar editDiag active
```
Expected: FAIL — an error/`unknown` because `editDiag` does not exist yet.

- [ ] **Step 2: Add the undo snapshot + `cancel()` to `services/BarEditState.qml`**

Add a private field `property var _snapshot: null`, a `readonly property bool canCancel: root._snapshot !== null`, and `function _captureSnapshot()` that deep-copies: `Settings.barLayoutIslands`, `Settings.barLayoutPill`, `Settings.barLayoutTop`, `Settings.barLayoutBottom`, `Settings.barLayoutFrame`, `Settings.barIslandsPos`. Call `_captureSnapshot()` at the top of `begin(style)`; set `root._snapshot = null` in `end()`. `cancel()` restores each captured value with `Settings.updateSetting(...)` (keys: `bar.layout.islands`, `bar.layout.pill`, `bar.layout.top`, `bar.layout.bottom`, `bar.layout.frame`, `bar.islands.pos`), then clears `_snapshot` and runs the same cleanup as `end()`.

- [ ] **Step 3: Add the IPC functions to `services/Ipc.qml`**

Add inside the `IpcHandler` (after `barDiag`): `edit`, `editCancel`, `editDone`, `editDiag` exactly as in the Interfaces block. `edit` calls `BarEditState`; `editCancel` calls `BarEditState.cancel()`; `editDone` calls `BarEditState.end()`.

- [ ] **Step 4: Reload and verify**

Run:
```bash
bash ~/.config/hypr/scripts/bar.sh; sleep 6
qs -p /home/bender/.config/quickshell/archeclipse ipc call bar editDiag active
qs -p /home/bender/.config/quickshell/archeclipse ipc call bar edit islands
qs -p /home/bender/.config/quickshell/archeclipse ipc call bar editDiag active
qs -p /home/bender/.config/quickshell/archeclipse ipc call bar editDiag canCancel
qs -p /home/bender/.config/quickshell/archeclipse ipc call bar editCancel
qs -p /home/bender/.config/quickshell/archeclipse ipc call bar editDiag active
grep -iE 'typeerror|referenceerror|binding loop|error' /tmp/qs-bar-$USER.log | tail -5
```
Expected: `false`, `editing islands`, `true`, `true`, `cancelled`, `false`, no log errors.

- [ ] **Step 4b: Verify reset-then-cancel (Review Focus 5)**

Run (capture the layout before entering, then after reset+cancel):
```bash
python3 -c "import json;print(json.load(open('/home/bender/.cache/quickshell/settings/settings.json'))['bar']['layout']['top']['value'])"
qs -p /home/bender/.config/quickshell/archeclipse ipc call bar edit islands
qs -p /home/bender/.config/quickshell/archeclipse ipc call bar editDiag reset
qs -p /home/bender/.config/quickshell/archeclipse ipc call bar editCancel
python3 -c "import json;print(json.load(open('/home/bender/.cache/quickshell/settings/settings.json'))['bar']['layout']['top']['value'])"
```
Expected: the two `top` arrays are identical — Cancel restores the entry layout even after a reset.

- [ ] **Step 5: qmllint + commit**

Run: `qmllint services/BarEditState.qml services/Ipc.qml` (expect exit 255, no output).
```bash
git add services/BarEditState.qml services/Ipc.qml
git commit -m "feat(bar): edit IPC entry/exit + undo snapshot"
```
(Only if the user asked to commit.)

---

## Task 2: Edit header chrome (Save / Cancel / Reset / hint) + Esc

**Files:**
- Modify: `widgets/bar/BarEditOverlay.qml` (replace the bottom `Reset default`/`Done` `Row` at lines 455–536)
- Test: CLI probe + `grim`

**Interfaces:**
- Consumes: `BarEditState.cancel()`, `BarEditState.end()` (Task 1).
- Produces: an overlay `id: header` `Rectangle` centered near the top of the bar band containing: a title `"Editing · " + (BarEditState.style === "pill" ? "Pill" : "Islands")`, a muted hint `"Drag to move · right-click to personalize · Esc to cancel"`, and three buttons — `Cancel` → `BarEditState.cancel()`, `Reset default` → `BarEditState.resetLayout()`, `Save` → `BarEditState.end()`.
- Produces: `Shortcut { sequence: "Escape"; context: Qt.ApplicationShortcut; enabled: BarEditState.active; onActivated: BarEditState.cancel() }`.

- [ ] **Step 1: Write the failing probe check**

Run:
```bash
qs -p /home/bender/.config/quickshell/archeclipse ipc call bar edit islands; sleep 1
grim -g "0,0 1920x140" /tmp/opencode/header_off.png
```
Expected: capture shows no header (feature absent).

- [ ] **Step 2: Replace the button row with the header**

Remove the existing `Row` (`Reset default` + `Done`, lines ~455–536). Add the `header` `Rectangle` (top-centered, `y` just below the band, `color: Theme.surface`, `border.color: Theme.accent`, rounded, `z` above everything) with the title/hint/buttons from Interfaces. Wire `Cancel`/`Reset default`/`Save` to the listed `BarEditState` calls.

- [ ] **Step 3: Add Esc**

Add the `Shortcut` from Interfaces as a child of `root`.

- [ ] **Step 4: Reload and verify**

Run:
```bash
bash ~/.config/hypr/scripts/bar.sh; sleep 6
qs -p /home/bender/.config/quickshell/archeclipse ipc call bar edit islands; sleep 1
grim -g "0,0 1920x300" /tmp/opencode/header_on.png
qs -p /home/bender/.config/quickshell/archeclipse ipc call bar editCancel
grep -iE 'typeerror|referenceerror|binding loop|error' /tmp/qs-bar-$USER.log | tail -5
```
Expected: `header_on.png` differs from a no-edit capture in the header region (header visible); `editCancel` runs clean; no log errors.

- [ ] **Step 4b: Manual check (user)**

Confirm the header text reads correctly and Esc cancels (report if Esc is not delivered because the bar window is not focusable).

- [ ] **Step 5: qmllint + commit**

Run: `qmllint widgets/bar/BarEditOverlay.qml`. Commit `feat(bar): edit-mode header with cancel/reset/save`.

---

## Task 3: Drag-only tray shelf

**Files:**
- Modify: `widgets/bar/BarEditOverlay.qml` (the `tray` Rectangle, lines ~370–436)
- Test: CLI probe + `grim`

**Interfaces:**
- Consumes: `BarEditState.draggingId`.
- Produces: the tray `visible` only while a drag is live — `visible: BarEditState.active && BarEditState.draggingId !== "" || (BarEditState.active && trayDragActive)` — concretely: `visible: BarEditState.active && (BarEditState.draggingId !== "")`, with an `opacity`/`y` `Behavior` (`Anim { type: Anim.DefaultSpatial }`) so it slides in.

- [ ] **Step 1: Write the failing probe check**

Run:
```bash
qs -p /home/bender/.config/quickshell/archeclipse ipc call bar edit islands; sleep 1
grim -g "0,900 1920x180" /tmp/opencode/tray_no_drag.png
```
Expected: the tray is visible with no drag (current behavior) — this is the wrong behaviour we are removing.

- [ ] **Step 2: Gate the tray on an active drag**

Add `visible: BarEditState.active && BarEditState.draggingId !== ""` to the `tray` `Rectangle`; keep it hidden otherwise. Add a `Behavior on opacity { Anim { type: Anim.DefaultSpatial } }` and drive `opacity: visible ? 1 : 0`.

- [ ] **Step 2b: Extend `editDiag` for a synthetic drag**

In `services/Ipc.qml` `editDiag`, add `"drag:<id>"` → sets `BarEditState.draggingId = id; BarEditState.dragFromZone = ""; BarEditState.dragEdge = "top"; BarEditState.dragX = 960; BarEditState.dragY = 700;` returns `"dragging " + id`; and `"drop"` → `BarEditState.clearLinearDrag(); return "cleared"`.

- [ ] **Step 3: Reload and verify**

Run:
```bash
bash ~/.config/hypr/scripts/bar.sh; sleep 6
qs -p /home/bender/.config/quickshell/archeclipse ipc call bar edit islands
qs -p /home/bender/.config/quickshell/archeclipse ipc call bar editDiag drag:clock; sleep 1
grim -g "0,900 1920x180" /tmp/opencode/tray_drag.png
qs -p /home/bender/.config/quickshell/archeclipse ipc call bar editDiag drop
grep -iE 'typeerror|referenceerror|binding loop|error' /tmp/qs-bar-$USER.log | tail -5
```
Expected: `tray_no_drag.png` shows no tray; `tray_drag.png` shows the tray; no log errors.

- [ ] **Step 4: qmllint + commit**

`qmllint widgets/bar/BarEditOverlay.qml services/Ipc.qml`; commit `feat(bar): tray is a drag-only shelf`.

---

## Task 4: Real-widget drag proxy (`grabToImage`)

**Files:**
- Modify: `widgets/bar/BarEditOverlay.qml` (the `surface.onPressed` handler and the floating proxy Rectangle, lines ~171–220 and ~438–454)
- Modify: `widgets/bar/DefaultBar.qml` (expose the delegate item for an id)
- Modify: `widgets/bar/pill/PillBar.qml` (same)
- Test: CLI probe + `grim`

**Interfaces:**
- Produces (DefaultBar/PillBar, reachable via `source`): `function cellItem(id: string) -> Item` — returns the rendered delegate `Item` (the Loader's `item`) for `id`, or `null`.
- Produces (BarEditOverlay): `property string proxySource: ""` (a `file://` URL or `""`) set once at drag start by `grabToImage`; the floating proxy draws an `Image { source: root.proxySource }` when non-empty, else the current chip.

- [ ] **Step 1: Write the failing probe check**

Run:
```bash
qs -p /home/bender/.config/quickshell/archeclipse ipc call bar edit islands
qs -p /home/bender/.config/quickshell/archeclipse ipc call bar editDiag drag:clock; sleep 1
grim -g "0,300 1920x500" /tmp/opencode/proxy_chip.png
```
Expected: the proxy is a text chip (feature absent).

- [ ] **Step 2: Add `cellItem(id)` to the bar faces**

In `DefaultBar.qml` (over `topRep`/`bottomRep`) and `PillBar.qml` (over the active rep): iterate the Repeater and return the matching delegate's `item` (reuse the Loader-resolution logic already in `_collectCells`). Return `null` when not found.

- [ ] **Step 3: Capture and draw the proxy image**

In `BarEditOverlay`, at the start of a left-press drag (both the `surface` press and the tray chip press), look up `root.source.cellItem(id)` and, if non-null, call `item.grabToImage(result => root.proxySource = result.url, Qt.size(item.width, item.height))`. Hide the widget's own content is **not** required (the preview reorder keeps it in place). Render `Image { source: root.proxySource; width: sourceSize.width; height: sourceSize.height }` inside the proxy when `proxySource !== ""`; keep the chip as fallback. Clear `proxySource` on release.

- [ ] **Step 4: Reload and verify**

```bash
bash ~/.config/hypr/scripts/bar.sh; sleep 6
qs -p /home/bender/.config/quickshell/archeclipse ipc call bar edit islands
qs -p /home/bender/.config/quickshell/archeclipse ipc call bar editDiag drag:clock; sleep 1
grim -g "0,300 1920x500" /tmp/opencode/proxy_image.png
grep -iE 'typeerror|referenceerror|binding loop|error' /tmp/qs-bar-$USER.log | tail -5
```
Expected: no errors; manual check that the widget image rides the pointer.

- [ ] **Step 5: qmllint + commit**

`qmllint widgets/bar/BarEditOverlay.qml widgets/bar/DefaultBar.qml widgets/bar/pill/PillBar.qml`; commit `feat(bar): real-widget drag proxy`.

---

## Task 5: Live reorder preview

**Files:**
- Modify: `services/BarEditState.qml`
- Modify: `widgets/bar/DefaultBar.qml`, `widgets/bar/pill/PillBar.qml`
- Create: `widgets/bar/EditStrip.qml`
- Test: CLI probe

**Interfaces:**
- Produces (BarEditState):
  - `previewOrder` (declared in Task 1) is now filled: `{ "<edge>": [ids...] }` while a linear drag is live, empty otherwise.
  - `previewSequence(style, edge)` returns `previewOrder[edge]` when a drag is live on that style+edge, else `BarWidgets.layoutLinear(style, edge)`.
  - `moveLinear(px, py, cells)` also recomputes `previewOrder[dragEdge]` = the current committed sequence with `draggingId` moved to `dropIndex`.
  - `clearLinearDrag()` and `commitLinearTo(...)` reset `previewOrder = ({})`.
- Produces (EditStrip): `EditStrip.qml`
  - `property var ids: []` (source sequence), `property Component delegate` (a `Component` whose root has `required property string modelData`), `property int spacing: Theme.spacing`.
  - Renders via an internal `ListModel` + horizontal `ListView` (`interactive: false`, `boundsBehavior: Flickable.StopAtBounds`, `width: contentWidth`, `height:` tallest delegate) with `move: Transition { NumberAnimation { properties: "x"; duration: 200; easing.type: Easing.OutCubic } }` and `add`/`remove` transitions using `Anim`.
  - `function syncIds()` reconciles the `ListModel` with `ids` (append/remove/`move`), so a reorder is a `ListModel.move()` (animates), not a rebuild.

- [ ] **Step 1: Write the failing probe check**

Run:
```bash
qs -p /home/bender/.config/quickshell/archeclipse ipc call bar edit islands
qs -p /home/bender/.config/quickshell/archeclipse ipc call bar editDiag move:1400
qs -p /home/bender/.config/quickshell/archeclipse ipc call bar editDiag preview
```
Expected: FAIL — `preview` returns `unknown query` (add `"preview"` → `JSON.stringify(BarEditState.previewOrder)` and `"move:<px>"` → drive `moveLinear` with the current edge cells to `editDiag` in this task's Step 2).

- [ ] **Step 2: Implement the preview data + `editDiag` queries**

In `BarEditState`: add `previewOrder`, compute it inside `moveLinear` (same-index math as `commitLinear`), clear it in `clearLinearDrag`/`commitLinearTo`; implement `previewSequence`. In `Ipc.editDiag`, add `"preview"` and `"move:<px>"` (calls `BarEditState.moveLinear(px, 0, BarEditState.cells)`).

- [ ] **Step 3: Prove the preview via probe (data only)**

```bash
bash ~/.config/hypr/scripts/bar.sh; sleep 6
qs -p ... ipc call bar edit islands
qs -p ... ipc call bar editDiag drag:clock
qs -p ... ipc call bar editDiag move:1400
qs -p ... ipc call bar editDiag preview
```
Expected: a JSON object whose `top` array has `clock` moved to the index implied by x=1400.

- [ ] **Step 4: Add `EditStrip.qml` and switch the faces to it**

Create `EditStrip.qml` per Interfaces. Extract each face's inline delegate into a named `Component` (its root must declare `required property string modelData`) and pass it as `EditStrip.delegate`. In `DefaultBar`, replace the `Row { Repeater { model: root.linearTopIds } }` and the bottom one with `EditStrip { ids: BarEditState.previewSequence("islands", "top"|"bottom"); delegate: ... }`, and make `linearTopIds/linearBottomIds` (used for cells/zones) read `BarEditState.previewSequence(...)`. In `PillBar`, replace `trackRow`/`trackEditRow` with one `EditStrip` over `BarEditState.previewSequence("pill","top")`.

Fallback (only if `EditStrip` proves unworkable in this Qt version): keep the `Row`+`Repeater` and accept instant relayout (no animation) — the deliverable is the live reorder, animation is the polish.

- [ ] **Step 4b: Per-widget lift + grip affordance (spec §2)**

In edit mode give each delegate a subtle lift — `scale: BarEditState.active ? 1.05 : 1.0` with `Behavior on scale { Anim { type: Anim.DefaultEffects } }`, plus a faint accent ring while `BarEditState.active`. The existing hover highlight (`_cellHoverId`/`_cellHoverRect`) already supplies the hover glow and the open-hand cursor, so no new hit-testing is needed. In `widgets/bar/DetachedPill.qml`, apply the same lift to each `Loader` while `BarEditState.active` (its per-widget `cells()` already feed the frame; whole-section dragging stays as-is).

- [ ] **Step 4c: Verify reorder + cross-edge/tray/empty-edge consistency (Review Focus 3, 4)**

With edit mode active, manually: (a) drag a widget within its edge and confirm neighbours slide; (b) drag it to the other edge and confirm it appears there and is gone from the first; (c) drag it off every strip and confirm it returns to the tray; (d) on a layout with a single widget, confirm no NaN geometry (`editDiag preview` stays valid JSON and the frame band renders). After each, reload and confirm the persisted `bar.layout.top`/`bar.layout.bottom` contain no duplicate or missing id:
```bash
python3 -c "import json;print(json.load(open('/home/bender/.cache/quickshell/settings/settings.json'))['bar']['layout'])"
```

- [ ] **Step 5: Reload + verify**

```bash
bash ~/.config/hypr/scripts/bar.sh; sleep 6
grep -iE 'typeerror|referenceerror|binding loop|error' /tmp/qs-bar-$USER.log | tail -5
```
Then manually drag a widget and confirm neighbours slide aside before release; confirm normal (non-edit) layout is unchanged.

- [ ] **Step 6: qmllint + commit**

`qmllint services/BarEditState.qml widgets/bar/EditStrip.qml widgets/bar/DefaultBar.qml widgets/bar/pill/PillBar.qml`; commit `feat(bar): live-reorder preview + animated strips`.

---

## Task 6: Frame-aware editing + "Frame follows drag"

**Files:**
- Modify: `theme/Settings.qml`
- Modify: `widgets/bar/Bar.qml`
- Modify: `widgets/bar/BarEditOverlay.qml` (add the toggle to the header)
- Test: CLI probe + `grim` pixel diff

**Interfaces:**
- Produces (Settings): `property bool barFrameFollowsDrag: true`; alias `"bar.edit.frameFollowsDrag": "barFrameFollowsDrag"` in `updateSetting`'s `aliases`; persistence writes `edit: { frameFollowsDrag: root.barFrameFollowsDrag }` under the `bar` object (near the `layout`/`islands` blocks, ~line 603); load reads `s.bar?.edit?.frameFollowsDrag` (near line 847) with default `true`.
- Produces (BarEditState): `function draggedBodyRect() -> var` — returns `{ id, zone, x, y, w, h }` for the widget currently under the pointer: `x = dragX - w/2`, `y = dragY - h/2`, `w`/`h` taken from the matching entry in `cells` (fallback `Theme.barContentHeight`), or `null` when no drag.
- Produces (Bar.qml): `_computeFrameBodiesList()` appends `root._frameCellBody(BarEditState.draggedBodyRect(), BarEditState.dragEdge, root.detached)` when `BarEditState.active && Settings.barFrameFollowsDrag && BarEditState.draggingId !== ""`.

- [ ] **Step 1: Write the failing check**

Run:
```bash
qs -p /home/bender/.config/quickshell/archeclipse ipc call bar editDiag frameFollows
```
Expected: FAIL — unknown query (add `"frameFollows"` → `String(Settings.barFrameFollowsDrag)` in this task).

- [ ] **Step 2: Add the setting**

In `theme/Settings.qml`: declare `barFrameFollowsDrag`, add the alias, add the persistence write under `bar`, and add the load read with default `true`.

- [ ] **Step 3: Add the dragged frame body**

In `BarEditState.draggedBodyRect()` (Interfaces). In `Bar.qml`, inside `_computeFrameBodiesList()` just before `return out;`, append the dragged body when the conditions hold (covers both pill and islands styles, since the append sits after every branch). Note: the **landing-slot** body needs no extra code — Task 5's preview reorder already places the dragged widget at the drop index, so its cell rect is in `cells` and `_computeFrameBodiesList` already frames it; `frameGeometryTick` re-samples every rendered frame so the band follows the reorder animation (do not animate inside the shader).

- [ ] **Step 4: Add the toggle to the edit header**

In `BarEditOverlay`'s header (Task 2), add an `AppCheckBox`-style control (or a small `AppSegmentedControl` On/Off) labeled `"Frame follows drag"` bound to `Settings.barFrameFollowsDrag` via `Settings.updateSetting("bar.edit.frameFollowsDrag", v)`.

- [ ] **Step 5: Reload + verify**

```bash
bash ~/.config/hypr/scripts/bar.sh; sleep 6
qs -p ... ipc call bar edit islands
qs -p ... ipc call bar editDiag drag:clock; sleep 1
grim -g "0,0 1920x140" /tmp/opencode/frame_drag_on.png
qs -p ... ipc call bar settingsSet bar.edit.frameFollowsDrag false   # or flip via editDiag
qs -p ... ipc call bar editDiag drag:clock; sleep 1
grim -g "0,0 1920x140" /tmp/opencode/frame_drag_off.png
grep -iE 'typeerror|referenceerror|binding loop|error' /tmp/qs-bar-$USER.log | tail -5
```
Expected: `frame_drag_on.png` differs from `frame_drag_off.png` in the pointer region; no log errors. If no settings-write IPC exists, flip the toggle through the header UI manually for the off capture.

- [ ] **Step 5b: Verify frame-disabled path (Review Focus 2)**

```bash
python3 -c "import json;p='/home/bender/.cache/quickshell/settings/settings.json';s=json.load(open(p));s['frame']['enable']={'value':False};json.dump(s,open(p,'w'),indent=1)"
bash ~/.config/hypr/scripts/bar.sh; sleep 6
qs -p ... ipc call bar edit islands
qs -p ... ipc call bar editDiag drag:clock
grep -iE 'typeerror|referenceerror|binding loop|error' /tmp/qs-bar-$USER.log | tail -5
```
Expected: no errors with the frame off; then restore `frame.enable=true` and reload.

- [ ] **Step 6: qmllint + commit**

`qmllint theme/Settings.qml widgets/bar/Bar.qml widgets/bar/BarEditOverlay.qml`; commit `feat(bar): dragged component carries its frame body`.

---

## Task 7: Bar entry affordance (hover grip)

**Files:**
- Modify: `widgets/bar/Bar.qml` (add inside `stripRoot`, above `editOverlay` ~line 1014)
- Test: reload + `ydotool` hover + `grim`

**Interfaces:**
- Produces: `Rectangle id: editHandle` anchored near the trailing edge of the bar band (top-right when `Settings.barOrientation`, else bottom-right), `visible: root.hovered && !BarEditState.active`, `opacity` animated (0 → 1) with `Behavior`, showing a pencil/grip glyph, `z` above the pill; a `MouseArea { onClicked: BarEditState.begin(Settings.barStyle) }`.

- [ ] **Step 1: Write the failing check**

Run: `grep -c "editHandle" widgets/bar/Bar.qml` → expected `0` (absent).

- [ ] **Step 2: Add the handle**

Add `editHandle` per Interfaces inside `stripRoot`.

- [ ] **Step 3: Reload + verify (hover)**

```bash
bash ~/.config/hypr/scripts/bar.sh; sleep 6
ydotool mousemove --absolute 960 5
sleep 0.5
grim -g "1500,0 420x80" /tmp/opencode/handle_hover.png
```
Note the ydotool absolute-coordinate scale in this session is ~2× (verify with `hyprctl cursorpos`); adjust so the cursor lands on the bar band. Expected: the grip glyph appears near the trailing edge. Then manually confirm clicking it enters edit mode.

- [ ] **Step 3b: Verify concealed-bar behavior (Review Focus 1)**

```bash
qs -p ... ipc call bar toggleBar eDP-1   # conceal
sleep 1; grim -g "1500,0 420x80" /tmp/opencode/handle_concealed.png
qs -p ... ipc call bar edit islands        # entry still works while concealed
qs -p ... ipc call bar editDiag active
```
Expected: no handle in `handle_concealed.png`; `editDiag active` returns `true` (IPC entry is independent of hover). Re-show the bar with `toggleBar`.

- [ ] **Step 4: qmllint + commit**

`qmllint widgets/bar/Bar.qml`; commit `feat(bar): hover grip to enter edit mode`.

---

## Task 8 (Pass 2): Settings Bar / Layout / Frame cards

**Files:**
- Modify: `widgets/leftPanel/SettingsWidget.qml` (Bar card ~lines 281–435; Frame card ~lines 437–667)
- Test: reload + `grim`

**Interfaces:**
- Consumes: `Card` from `qs.widgets.shared`; `BarEditState.begin(style)`, `BarEditState.resetLayout()`.
- Produces: three `Card`s — **Bar** (style combo, orientation, Lock Bar, Always Expanded, reveal pressures, Player Visualizer), **Layout** (prominent `Edit layout` button → `BarEditState.begin(Settings.barStyle)`, `Reset` → `resetLayout()`, detached-sections toggle shown only for islands), **Frame** (the existing frame controls, kept and grouped; rows stay hidden when `Settings.shellFrame` is false).

- [ ] **Step 1: Write the failing check**

Run: `grep -c 'title: "Layout"' widgets/leftPanel/SettingsWidget.qml` → expected `0`.

- [ ] **Step 2: Split the Bar card**

Reorder the existing controls into the three `Card`s from Interfaces, reusing the current control snippets verbatim; add `AppTooltip`s to the controls whose effect is not obvious (reveal pressures, music swell strength).

- [ ] **Step 3: Reload + verify**

```bash
bash ~/.config/hypr/scripts/bar.sh; sleep 6
grep -iE 'typeerror|referenceerror|binding loop|error' /tmp/qs-bar-$USER.log | tail -5
```
Open Settings → Bar; confirm the three cards render and `Edit layout` still enters edit mode.

- [ ] **Step 4: qmllint + commit**

`qmllint widgets/leftPanel/SettingsWidget.qml`; commit `feat(settings): group bar controls into Bar/Layout/Frame cards`.

---

## Verification (whole change, before declaring done)

- `qmllint` every touched file (exit 255, no output = baseline PASS).
- `bash ~/.config/hypr/scripts/bar.sh`; grep `/tmp/qs-bar-$USER.log` for `typeerror|referenceerror|binding loop|error` (expect none).
- Probe matrix via `qs -p /home/bender/.config/quickshell/archeclipse ipc call bar ...`: `edit`/`editDiag active`/`editDiag preview`/`editCancel`/`editDone`.
- Enter edit via IPC, capture with `grim`, verify the header, the dragged frame body, and (during a synthetic drag) the tray shelf.
- Confirm non-edit rendering is unchanged (frame band + components still fused) in both pill and islands styles.
- Restore the user's live settings (`bar.style=pill`, `bar.islands.detached=true`, `frame.enable=true`) if any probe changed them; remove any temporary diagnostic code.
- Do not commit unless the user asks; stage only the files above.
