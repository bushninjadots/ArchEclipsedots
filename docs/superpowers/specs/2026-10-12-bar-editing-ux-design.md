# Bar Editing UX Design

Date: 2026-10-12
Status: Draft (approved)
Scope: Editing experience for both bar styles (pill + islands), the Settings
bar-layout controls, and how component moves compose with the shell frame.

## Intent & Success Criteria

Make editing both bar styles feel direct and predictable, make the Settings
bar controls clearer and nicer, and make moving separate components visual and
functional — composed with the shell frame rather than fighting it.

Success criteria (all must hold):

- Edit mode is obvious to enter and leave; entering never requires a trip to
  Settings (Settings entry is kept).
- While dragging a widget, the landing position is visible **before release**
  (a ghost/landing slot), and neighbours reorder **live**.
- The shell frame participates: the band opens at the landing slot and the
  dragged widget carries its frame body with it.
- **Cancel/undo** exists (revert to the layout captured on entry), in addition
  to reset-to-default.
- Bar / Layout / Frame settings are grouped, labeled, and self-explanatory.
- No regression to normal (non-edit) rendering; existing frame correctness
  (per-component bodies) is preserved.

## Non-goals

- No changes to `frame.frag` / the body mechanism (the fixed-slot individual
  uniforms from the previous fix stay).
- No new widget types and no changes to widget internals.
- No change to the persisted layout schema, except one optional toggle
  (`frame follows drag`).

## Current State (as-is)

- `services/BarEditState.qml` — edit state machine: `active`, `draggingId`,
  `dragFromZone`, `dragX/dragY`, linear drag (`dragIndex`, `dropIndex`,
  `dragEdge`), section drag (`dragSection`, `dragSectionX/Y`), `cells`,
  `dropZones`, commit helpers (`place`, `remove`, `dropAt`, `commitLinearTo`,
  `commitSection`, `resetLayout`), per-widget `frameFor`/`setFrame`.
- `widgets/bar/BarEditOverlay.qml` — full-window layer (z=1000): dashed zone
  outlines + labels, bottom always-on **tray** of unplaced widgets, floating
  text-chip **drag proxy**, a 4px insertion line, per-widget personalize
  popover, and Reset/Done buttons. Polls geometry every 150ms.
- Bar faces publish geometry: `DefaultBar.editCells()/editZones()` (top/bottom
  strips), `pill/PillBar.editCells()/editZones()` (single track; uses
  `trackEditRep` while editing), `DetachedPill.cells()` (per section).
- `widgets/bar/Bar.qml` builds `frameBodiesList` from those cells
  (`_frameCellBody` applies the per-widget shape); `FrameAnimation` +
  `frameGeometryTick` re-evaluate per rendered frame.
- Entry is **only** from `SettingsWidget` "Edit layout". There is no Cancel or
  undo snapshot.

## Design

### 1. Edit mode as a real bar state (entry / exit / chrome)

**Entry**
- A small pencil/grip button that fades in at the bar's trailing edge on hover
  (normal mode only) → `BarEditState.begin(style)`.
- New IPC command `bar edit` (IpcHandler target `bar`, function `edit()`) so it
  can be bound to a Hyprland shortcut: `qs ipc call bar edit`.
- The existing Settings **"Edit layout"** buttons stay.

**Exit**
- Slim **header** pinned near the band (just outside it, inset so it does not
  collide with the frame): `Editing · Pill|Islands`, a one-line hint
  ("drag to reorder · right-click a widget for its frame shape · Esc to
  cancel"), and `Save` · `Cancel` · `Reset default`.
- `Esc` = Cancel (revert to the entry snapshot). Click-away or `Done`/`Save` =
  save. `Reset default` = existing `resetLayout()`.

**Undo snapshot**
- On `begin(style)`, capture a snapshot of: the active style's zone model, the
  two linear sequences (`bar.layout.top` / `bar.layout.bottom`), detached
  positions (`bar.islands.pos`), and per-widget frames (`bar.layout.frame`).
- `cancel()` restores that snapshot through `Settings.updateSetting` (memory +
  disk in lock-step, same as `resetLayout`).
- Snapshot is transient (in-memory only) — never persisted.

### 2. Direct manipulation & reorder feel

- Each placed widget in edit mode gets a subtle **lift** (small scale/shadow)
  and a grip affordance; cursor open-hand; hover glow on the widget under the
  pointer.
- On drag: the widget lifts into a drag layer, its source slot collapses, and a
  **ghost placeholder** (drawn in the widget's own frame shape) marks the
  landing spot. Neighbours **animate aside live** (icon-grid reordering) using
  the shared `Anim` spring, so the result is visible before release.
- Cross-edge moves (top↔bottom for islands; into/out of the bar) reorder across
  edge sequences; a drop outside every strip returns the widget to the tray.
- The **tray becomes a drag-only shelf**: hidden whenever no drag is in flight;
  it slides in when a drag starts and hides on release, so normal edit mode is
  uncluttered. (Discoverability is covered by the header hint and the fact that
  dropping outside the strips returns a widget to the tray.)
- **Live reorder** is driven by a transient `previewOrder` on `BarEditState`
  (the sequence as it would look if dropped now); the faces render from the
  preview sequence during a drag and the pointer's insertion index is applied to
  it on release.
- **Detached islands**: section pills are directly draggable (with basic
  alignment/snapping guides); widgets move between sections the same way.
- The drag proxy renders the **real widget**, captured with
  `Item.grabToImage` at drag start, instead of a text chip.

### 3. Frame-aware editing (core new piece)

- While editing, `Bar.qml`'s `frameBodiesList` additionally includes:
  - the **ghost landing slot** body, and
  - the **dragged widget's body at the pointer** (reduced opacity),
  using the widget's configured shape so the preview matches the result.
- Remaining widgets keep one continuous band; on drop the geometry re-commits
  and the frame **animates** into place rather than popping.
- A small toggle **"Frame follows drag"** (default on) gates the extra bodies.
- Implementation note: bodies are recomputed per rendered frame already. To get
  smoothness, animate the **source rects** (the ghost rect and the cell rects
  during live reorder) and let `frameGeometryTick` pick them up — rather than
  animating inside the shader.

### 4. Settings UI reorganization (Pass 2)

- Split the monolithic **Bar** card into sub-cards using the shared `Card`
  component and headings:
  - **Bar** — style, orientation, lock, always-expanded, reveal pressures,
    player visualizer.
  - **Layout** — per active style: a prominent "Edit layout" button, Reset, and
    the detached-sections toggle (islands only).
  - **Frame** — shell style, thickness, radius, music swell (+ edges/strength),
    color, tint, opacity, border (+ color/width).
- Frame rows stay hidden when Shell Style = Floating (already the case) so the
  section never looks broken.
- Add short tooltips for controls whose effect is not obvious.

## Data model / persistence

- New transient (not persisted): edit **undo snapshot** in `BarEditState`.
- New optional persisted key: `bar.edit.frameFollowsDrag` (bool, default true).
- Everything else uses existing keys: `bar.layout.top`, `bar.layout.bottom`,
  `bar.layout.islands`, `bar.layout.pill`, `bar.layout.frame`,
  `bar.islands.pos`, `bar.style`, `bar.islands.detached`.

## Interaction details

- Grab hit-testing expands cell rects by a small margin so thin widgets are
  still easy to grab.
- Insertion index keeps the current rule (pointer x vs cell midpoints); the new
  part is applying it as a **live preview** (reorder the visible sequence) and
  committing on release.
- Exit: `Esc` cancels; click-away / `Done` saves; `Reset default` restores code
  defaults.
- Personalize popover (per-widget frame shape + radius) is unchanged in
  behaviour; only its trigger affordance may move to the new grip.

## Files touched

- `services/BarEditState.qml` — undo snapshot, live-reorder preview, ghost
  state, entry-from-bar API.
- `widgets/bar/BarEditOverlay.qml` — header (Save/Cancel/Reset + hint),
  drag-only tray shelf, real-widget ghost via `grabToImage`, restyled
  affordances, Esc handling.
- `widgets/bar/DefaultBar.qml`, `widgets/bar/pill/PillBar.qml`,
  `widgets/bar/DetachedPill.qml` — per-widget affordances, live reorder
  animation, geometry.
- `widgets/bar/Bar.qml` — frame ghost/dragged bodies, hover entry affordance,
  Esc wiring.
- `widgets/leftPanel/SettingsWidget.qml` — Bar/Layout/Frame cards (Pass 2).
- `services/Ipc.qml` — `bar edit` command.

## Testing / verification

- `qmllint` touched files; reload via `~/.config/hypr/scripts/bar.sh`; grep
  `/tmp/qs-bar-$USER.log` for `typeerror|referenceerror|binding loop|Error`.
- Pixel probes: enter edit mode via `qs ipc call bar edit`, capture with `grim`,
  verify the frame band + the ghost/dragged body render.
- Manual feel check by the user (drag precision, live reorder, frame preview).

## Risks / open questions

- `grabToImage` at drag start: cost and whether the widget can be captured
  before it is hidden. Mitigation: capture, then hide the source.
- Animating frame bodies must not fight `frameGeometryTick`; the chosen approach
  animates the source rects, not the shader.
- Detached-section alignment guides are optional polish; ship plain free move
  first.

## Staging

- **Pass 1** — §1 entry/exit/chrome (incl. undo snapshot), §2 direct
  manipulation + live reorder + real ghost, §3 frame-aware editing.
- **Pass 2** — §4 Settings card reorganization (+ optional polish).

## As built (2026-10-12, rework)

The freeform linear model (`bar.layout.top/bottom`) was removed: it flattened both
bars, lost the original islands/pill looks and was shared between styles. The
editor now works on per-style SECTIONS (islands left/center/right/bottom, pill
rest/core/detail) with any widget allowed in any section; defaults are the
original layouts.

- Live drag preview (`BarEditState.ids`), ghost at the landing slot, stable
  insertion index, sticky section targeting, drop on the shelf to hide.
- Click = inspector (section, ←/→, hide, frame shape, radius, pill, opacity);
  keyboard ←/→ order, ↑/↓ section, Del hide, Esc, Enter.
- Header: style switch, Detach/Attach, Undo all, Reset default, Cancel, Done.
  Cancel also restores style + detached.
- Per-widget decoration pill (none/border/filled) + opacity, global defaults in
  Settings → Bar → Widgets.
- Frame: bodies per section run, keyed and morphed (spring/smooth/instant),
  bodies merge into each other (Section Merge), per-body fillet (iNiR-style),
  bodies near a screen side seat flush into it, music lift centred on the bar
  and a treble shimmer on the contour.
- Hyprland window border colour can follow accent / wallpaper / album / custom.
