# Bar Layout System — Design

- Date: 2026-10-10
- Status: Draft (uncommitted — repo rule: do not commit unless explicitly asked)
- Scope: configurable bar layout for the ArchEclipse Quickshell bar

## 1. Context

The shell currently ships two interchangeable bar styles selected by `Settings.barStyle`:

- **islands** — `widgets/bar/DefaultBar.qml` builds a fixed arrangement: a left zone
  (`ResourceMonitor`, `WeatherButton`), a centred pill (bandwidth, `ControlPanelButton`,
  `Clock`), a right zone (`Media`, `Battery`, `Brightness`, `Volume`, `Tray`), and a
  bottom `Workspaces` strip.
- **pill** — `widgets/bar/pill/PillBar.qml` builds a rest face (dots · clock · chip) that
  morphs on hover into an expanded face (core row: music/bandwidth · clock · control;
  detail row: weather · resources · battery · brightness · volume · network · tray).

`widgets/bar/Bar.qml` is the shared panel-window surface; it hosts whichever style is
selected and owns the pill float/rounding, the side pulses, and the search overlay.

Both layouts are hard-coded. The Bar section of the left-panel Settings
(`widgets/leftPanel/SettingsWidget.qml`) is a single flat card that mixes shared options,
shell-frame options, and the bar-style switch.

## 2. Goals

1. **Per-style option sections** — options that only apply to a bar style are grouped under
   that style; shared options stay general.
2. **Rearrangeable layout** — move components around and place them where wanted, per style:
   reorder, regroup, **add**, and **remove** widgets.
3. **WYSIWYG drag** — arrange by dragging directly on the bar in an edit mode.
4. **Detachable islands** — an islands option to break the continuous bar apart into one floating
   pill per section, each freely placed on screen (see §5.1).
5. Keep both existing styles working with no visual change out of the box.

## 3. Non-goals

- **Component variants** (alternate looks/behaviours per component, e.g. clock text vs icon).
  Explicitly deferred to a later stage (Stage 2); the model must not preclude it.
- User-created/custom zones (zones are fixed per style).
- Multiple instances of the same widget per style (one of each).
- Cross-window drag (bar ↔ Settings panel is impossible; the palette lives in the bar window).
- Detached islands splitting below section granularity (a section stays one pill; it is not broken
  into per-widget pills), and detaching the **pill** style (detachment is islands-only).

## 4. Success criteria

- Each style's layout is persisted in `settings.json` and survives reload.
- In edit mode a widget can be dragged between allowed zones, added from a tray, and removed;
  changes persist and render immediately.
- With islands `Detached` on, sections become independent floating pills that can be dragged
  anywhere on screen and that reload in the same places.
- Defaults reproduce the current layouts exactly.
- No regressions: `qmllint` clean, reload logs free of `typeerror`/`referenceerror`/binding
  loops, both styles and both bar orientations behave.

## 5. Architecture (Approach A — model-driven bar)

A per-style **layout model** drives both bars. Each style has fixed **zones**; each zone is an
ordered list of **widget ids**. A widget **catalog/registry** maps a widget id, style, and zone
to the `Component` that renders it. Zones render by repeating over their list and loading the
mapped component. Edit mode mutates the model and persists it; rendering follows automatically.

### Zones

| Style | Zones |
|---|---|
| islands | `left`, `center`, `right`, `bottom` |
| pill | `rest`, `core`, `detail` |

### Widget catalog

Every widget may only be placed in zones it supports (a widget can render differently, or not at
all, per style/face). Proposed catalog and allowed zones:

| id | label | islands | pill |
|---|---|---|---|
| `workspaces` | Workspaces | bottom | rest |
| `clock` | Clock | center | rest, core |
| `media` | Media | right | core |
| `bandwidth` | Bandwidth | center | core |
| `control` | Control Panel | center | core |
| `chip` | Live Chip | — | rest |
| `weather` | Weather | left | detail |
| `resources` | Resources | left | detail |
| `battery` | Battery | right | detail |
| `brightness` | Brightness | right | detail |
| `volume` | Volume | right | detail |
| `network` | Network | right | detail |
| `tray` | System Tray | right | detail |

### Default layouts (reproduce today)

- islands.left = `[resources, weather]`
- islands.center = `[bandwidth, control, clock]`
- islands.right = `[media, battery, brightness, volume, tray]`
- islands.bottom = `[workspaces]`
- pill.rest = `[workspaces, clock, chip]`
- pill.core = `[media, bandwidth, control, clock]` (bandwidth shown only when no media — existing
  behaviour preserved in the renderer)
- pill.detail = `[weather, resources, battery, brightness, volume, network, tray]`

Widgets absent from a list are "available" (pooled in the edit tray). An empty zone simply
renders nothing.

### 5.1 Detached islands (break-apart)

An islands-only option, `Detached` (default off), breaks the single continuous bar into **one
floating pill per section** — `left`, `center`, `right`, `bottom`. Each pill renders the same zone
contents as the attached bar; only the surface and placement change.

- **Placement:** in edit mode each section pill can be dragged anywhere on screen; its position is
  saved as an absolute top-left `(x, y)` in logical pixels. The pills are independent — no shared
  row, alignment, or full-width surface.
- **Defaults:** a section that has never been positioned starts at today's attached position for
  that section (left/center/right along the top edge, `bottom` along the bottom edge).
- **Attached remains the default** and is visually identical to the current bar.
- **Multi-monitor:** v1 stores a single `(x, y)` per section on the primary output; per-output
  placement is deferred (see §12).

## 6. Registry

New singleton `theme/BarWidgets.qml` (or `services/BarWidgets.qml`):

- `catalog` — array of `{ id, label, icon, zones: { islands: [...], pill: [...] } }`.
- `component(id, style, zone)` — returns the `Component` for that widget in that context
  (an internal map of `Component`s; reuses existing widget files and wrappers such as
  `PillMusic`). Widgets whose rendering differs by zone (e.g. `workspaces` strip vs dots)
  return the appropriate component for the (style, zone) pair.
- `allowed(id, style, zone)` — helper used by the drag validation and the settings UI.

## 7. Rendering

- Each zone becomes a container (Row/RowLayout) that `Repeater`s over the zone's id list and
  instantiates `Loader { sourceComponent: BarWidgets.component(id, style, zone) }`.
- Zone layout, spacing, alignment, and sizing keep the current visual values
  (`Theme.barContentHeight`, zone spacing, centred `center`/`core` rows).
- `DefaultBar.qml` and `PillBar.qml` are refactored to read the model rather than hard-code
  children.
- **Attached mode:** `Bar.qml` keeps its current single top/bottom-anchored `PanelWindow` surface
  (plus the edit overlay).
- **Detached islands mode:** `Bar.qml` instead mounts a full-output, transparent `PanelWindow`
  (layer surface) whose input `mask` is the union of the section-pill rectangles and whose
  exclusion is derived from those rectangles; each section pill is absolutely positioned inside it
  as its own rounded surface. Only the pills intercept input (via the mask), so the desktop stays
  clickable between them.
- Existing widget files (`Clock.qml`, `Battery.qml`, `PillChip.qml`, …) stay as-is; only their
  placement moves behind the registry.

## 8. Edit mode

- A shared flag (new `services/BarEditState.qml`, or an extension of `BarState`) drives edit mode.
- **Entry:** an "Edit bar layout" button in each style's Settings section, and optionally a
  keybind.
- **Presentation:** the bar locks open (hover-expand and auto-hide suppressed). Zones show dashed
  outlines; each placed widget gains a grab look. A **tray row** below the bar lists that style's
  available (unplaced) widgets. For the pill, all three zones (`rest`, `core`, `detail`) are shown
  stacked as distinct drop targets; a **Done** button exits.
- **Drag mechanics:** a lightweight in-window proxy — a floating chip follows the cursor and drop
  zones hit-test against it (no cross-window DnD, no `Drag`/`DropArea` across surfaces).
- **Rules:** tray → allowed zone = add; zone → allowed zone = move (order follows drop position);
  zone → tray = remove. Invalid drops are rejected (zone not allowed for that widget). A widget is
  listed in the tray when it is placed in no zone of the style; if it is placed in any zone it is
  marked as placed.
- **Detached islands:** when `Detached` is on, a section pill can be dragged anywhere on screen
  (not only between zones); the drop records its new `(x, y)`. Dragging an individual widget still
  follows the normal zone rules (tray/zone add, move, remove).
- **Persistence:** live — each drop writes to the model and `Settings.persist()`.
- **Interactions to neutralise while editing:** islands hover pulses (`BarState.activate`) and the
  pill hover-expand/`leaveTimer`; the rest face's `enabled: t < 0.5` gating; widget-level clicks
  (transport, popups) that would otherwise fire during a drag.

## 9. Settings UI

The flat Bar card is split into sections (reusing the existing card + `RowLayout` + `App*`
control pattern):

- **Bar · General** — Orientation, Lock Bar, Always Expanded, Reveal-In/Out Pressure.
- **Bar · Islands** — islands-specific options (e.g. island inset/padding), a **Detached** toggle
  (break into per-section floating pills), and **Edit bar layout**.
- **Bar · Pill** — pill-specific options (e.g. chip content, spectrum visibility/opacity,
  rest/expanded spacing) + **Edit bar layout**.
- **Frame** — the existing `frame*` rows (gated on `Settings.shellFrame`).
- **Bar Style** — the islands/pill switch stays accessible (General or its own row).

Per-style rows are `visible:`-gated on `Settings.barStyle` where appropriate.

## 10. Persistence & migration

- `settings.json`:
  - `bar.layout.islands.{left,center,right,bottom}` → `string[]`
  - `bar.layout.pill.{rest,core,detail}` → `string[]`
  - `bar.islands.detached` → `bool` (default `false`)
  - `bar.islands.pos.{left,center,right,bottom}` → `{ x, y }` logical px (meaningful only when
    detached; absent → the default position for that section)
- `theme/Settings.qml` gains matching properties with `persist` aliases and the existing
  tolerant reload pattern.
- Missing/empty keys fall back to the default layouts in §5, so existing users see no change.
- Unknown widget ids are ignored on load (forward-compatible).

## 11. Verification

- `qmllint` on every touched file; reload via `~/.config/hypr/scripts/bar.sh`; grep
  `/tmp/qs-bar-$USER.log` for `typeerror|referenceerror|binding loop`.
- Manual matrix: both styles × both orientations; enter/exit edit mode; add, move (valid and
  invalid targets), remove; reload and confirm persistence; confirm default layouts unchanged.
- Detached islands: toggle on, confirm four independent pills; drag each and confirm positions
  persist across reload; toggle off and confirm the continuous bar returns; confirm the desktop
  between pills is still clickable.

## 12. Risks & open questions

- **Clock duplication:** the pill shows a clock in both `rest` and `core`. **Decision:** a widget id
  may appear at most once per *zone*; the same id may appear in more than one zone of a style
  because the faces are distinct surfaces. The one-of-each constraint applies *within* a zone.
  Revisit if it looks odd.
- **Edit-mode rendering of the pill** (all three zones stacked) is a special layout that must not
  leak into normal rendering.
- **Tight drag targets** in the ~32 px bar; the proxy and hit areas need generous margins.
- **`Bar.qml` width animation** and the dynamic pill width must cope with zone contents changing.
- **Detached surface strategy:** switching between the anchored bar window and the full-output
  masked overlay window when `Detached` toggles; ensure anchors/exclusion/mask swap cleanly with no
  ghost surface left hovering.
- **Multi-monitor detached placement:** v1 coordinates are primary-output logical pixels; a pill
  dragged to another monitor, or after a monitor/scale change, may sit wrong. Per-output storage is
  deferred.

## 13. Staged plan

- **Stage 1 (this spec):** zone/model + registry, refactor both bars, edit mode + tray, Settings
  split, persistence, verification.
- **Stage 1b (this spec):** islands `Detached` break-apart — per-section floating pills + free
  placement, built on the Stage 1 model.
- **Stage 2 (later):** component variants (alternate views/styles) built on the registry.
