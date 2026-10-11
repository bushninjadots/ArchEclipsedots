# Bar Layout System Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the ArchEclipse bar (islands + pill styles) into a data-driven, per-style, user-rearrangeable layout with a drag-on-the-bar edit mode and optional detachable islands sections.

**Architecture:** A singleton registry (`services/BarWidgets.qml`) owns the widget catalog and produces `Component`s per `(id, style, zone)`. `theme/Settings.qml` persists the layout model (`bar.layout.islands`, `bar.layout.pill`), plus detached/position state. `DefaultBar.qml` and `pill/PillBar.qml` keep their existing visual chrome but render each zone by `Repeater`ing `Loader`s over the model. An edit-mode singleton (`services/BarEditState.qml`) + overlay (`widgets/bar/BarEditOverlay.qml`) add dashed zones, a widget tray, and floating-proxy drag. Detached islands render as one masked full-output layer window with one pill per section (`widgets/bar/DetachedBar.qml`).

**Tech Stack:** Quickshell (QML / Qt 6), `qs.*` modules, PipeWire/cava via existing `AudioBars`, Nerd Font glyphs. No test framework — verification is `qmllint` + bar reload log inspection + live/manual checks.

**Spec:** `docs/superpowers/specs/2026-10-10-bar-layout-system-design.md`

## Global Constraints

- **Do NOT run `git commit` / `git push`.** Standing repo rule: commit only when the user explicitly asks. Stage nothing unless asked.
- Never `git add .`; only named, touched files if staging is ever requested.
- Zones — islands: `left`, `center`, `right`, `bottom`. Pill: `rest`, `core`, `detail`.
- Widgets allowed per style/zone (verbatim from spec): `workspaces` (islands `bottom`; pill `rest`), `clock` (islands `center`; pill `rest`+`core`), `media` (islands `right`; pill `core`), `bandwidth` (islands `center`; pill `core`), `control` (islands `center`; pill `core`), `chip` (pill `rest` only), `weather` (islands `left`; pill `detail`), `resources` (islands `left`; pill `detail`), `battery`/`brightness`/`volume`/`network`/`tray` (islands `right`; pill `detail`).
- Default layouts MUST reproduce today's arrangement byte-for-behaviour: islands `left=[resources,weather]`, `center=[bandwidth,control,clock]`, `right=[media,battery,brightness,volume,tray]`, `bottom=[workspaces]`; pill `rest=[workspaces,clock,chip]`, `core=[media,bandwidth,control,clock]`, `detail=[weather,resources,battery,brightness,volume,network,tray]`.
- A widget id may appear **at most once per zone**; it MAY appear in more than one zone of a style (pill `rest`/`core` are different surfaces).
- Existing widget files (`Clock.qml`, `Battery.qml`, `MprisWidget.qml`, `PillChip.qml`, …) keep their public props; add new wrappers rather than rewriting them.
- Reload the bar with `~/.config/hypr/scripts/bar.sh` (SUPER+B). Its shell output is cut by SIGTERM — inspect `/tmp/qs-bar-$USER.log` separately.
- `qmllint` may exit `255` with zero output for files importing `qs.*` (env baseline) — that is PASS. Exit `0` with no output is also PASS. Any printed diagnostic is FAIL.
- Persisted settings live at `~/.cache/quickshell/settings/settings.json`; code defaults must keep working for users who never open the editor.

## Review Focus

Inputs/conditions the spec implies but no task's tests cover directly — each is pinned by a verification step in the owning task:

1. **Empty zone / empty layout** (user removes every widget from a style) → bar renders empty zones without crashing or collapsing the surface. (Task 3/4)
2. **Unknown or disallowed id in persisted JSON** (hand-edited or from a future version) → silently dropped, never instantiated. (Task 2)
3. **Duplicate id within one zone** → rendered once. (Task 2/3)
4. **Detached mode with unresolved position** (`x=-1,y=-1`) → resolves to the section's default on-screen anchor, never draws at `(-1,-1)`. (Task 8)
5. **No MPRIS player** → `media`/`chip`/spectrum gates all fold to hidden, no errors. (Task 2/4)

---

### Task 1: Settings layout model + persistence

**Files:**
- Modify: `theme/Settings.qml` (bar block ~line 22; `updateSetting` aliases ~line 347; `persist()` ~line 439; reload block ~line 667)

**Interfaces:**
- Produces (readable anywhere as `Settings.*`):
  - `property var barLayoutIslands` :: `{ left: string[], center: string[], right: string[], bottom: string[] }`
  - `property var barLayoutPill` :: `{ rest: string[], core: string[], detail: string[] }`
  - `property bool barIslandsDetached`
  - `property var barIslandsPos` :: `{ left:{x:int,y:int}, center:{...}, right:{...}, bottom:{...} }` (`-1` = unset)
- Consumed by: Tasks 2, 3, 4, 5, 7, 8, 9.

- [ ] **Step 1: Declare the properties** in the bar block (after `barStyle`, ~line 22):

```qml
property var barLayoutIslands: ({
    left: ["resources", "weather"],
    center: ["bandwidth", "control", "clock"],
    right: ["media", "battery", "brightness", "volume", "tray"],
    bottom: ["workspaces"]
})
property var barLayoutPill: ({
    rest: ["workspaces", "clock", "chip"],
    core: ["media", "bandwidth", "control", "clock"],
    detail: ["weather", "resources", "battery", "brightness", "volume", "network", "tray"]
})
property bool barIslandsDetached: false
property var barIslandsPos: ({
    left: ({ x: -1, y: -1 }), center: ({ x: -1, y: -1 }),
    right: ({ x: -1, y: -1 }), bottom: ({ x: -1, y: -1 })
})
```

- [ ] **Step 2: Add aliases** to the `updateSetting` aliases map: `"bar.layout.islands" -> "barLayoutIslands"`, `"bar.layout.pill" -> "barLayoutPill"`, `"bar.islands.detached" -> "barIslandsDetached"`, `"bar.islands.pos" -> "barIslandsPos"`.

- [ ] **Step 3: Persist the keys** in `persist()`'s JSON tree under `bar`: `layout: { islands: barLayoutIslands, pill: barLayoutPill }`, `islands: { detached: barIslandsDetached, pos: barIslandsPos }`. Keep existing keys untouched.

- [ ] **Step 4: Assign on reload** in the tolerant reload block (inside the `ready`-gated assignment), using null-safe fallbacks so a missing key keeps the default:
  `if (j.bar?.layout?.islands) barLayoutIslands = j.bar.layout.islands` (and likewise pill/detached/pos).

- [ ] **Step 5: Verify**

Run: `qmllint theme/Settings.qml`
Expected: PASS (0 or 255, no diagnostics).
Run: `~/.config/hypr/scripts/bar.sh` then `grep -niE "typeerror|referenceerror|invalid property|binding loop" /tmp/qs-bar-$USER.log`
Expected: `Configuration Loaded`, no matches.
Run: `python3 -c "import json;d=json.load(open('/home/bender/.cache/quickshell/settings/settings.json'));print(d.get('bar',{}).get('layout'))"`
Expected: after Task 5 changes anything it shows the new keys; at this task it may print `None` (defaults not yet written) — that is acceptable.

---

### Task 2: Widget registry + media cell extraction

**Files:**
- Create: `services/BarWidgets.qml`
- Create: `widgets/bar/MediaCell.qml`
- Modify: `services/qmldir` (register `BarWidgets`)
- Modify: `widgets/bar/qmldir` (register `MediaCell`)
- Modify: `widgets/bar/DefaultBar.qml` (later tasks consume `MediaCell`; here only ensure it exists)

**Interfaces:**
- Produces `BarWidgets` (singleton):
  - `readonly property var catalog` :: `[{ id, label, icon, zones: { islands: string[], pill: string[] } }]`
  - `readonly property var firstPlayable` :: first real MPRIS player (`null` when none)
  - `function allowed(id: string, style: string, zone: string) -> bool`
  - `function layout(style: string, zone: string) -> string[]` — deduped, filtered by `allowed`, from `Settings.barLayoutIslands|Pill`
  - `function component(id: string, style: string, zone: string) -> Component`
  - `function label(id: string) -> string`, `function icon(id: string) -> string`
- Produces `MediaCell` (islands media wrapper): `Rectangle` with `visible: BarWidgets.firstPlayable !== null`, `implicitWidth: mprisWidget.implicitWidth + 16`, `implicitHeight: Theme.barContentHeight`; contains `MprisWidget { fullMode: Settings.mprisVisualizer }` + full-surface `MouseArea` (left→toggle player island, right→toggle `Settings.mprisVisualizer`+persist, middle→`togglePlaying`, wheel→next/prev).

- [ ] **Step 1: Write the catalog** in `BarWidgets.qml` covering all 13 ids with the Global-Constraints zones. `firstPlayable` uses the existing `MprisWidget` ghost-filter (`/playerctld/i`). `layout()` reads `Settings.barLayoutIslands`/`barLayoutPill`, filters with `allowed()`, and de-duplicates preserving order.

- [ ] **Step 2: Write `component(id, style, zone)`.** Return `null` for disallowed/unknown combos (callers MUST guard). Private `Component`s reuse existing widgets; add thin wrappers only where rendering differs by style, e.g.:
  - `workspaces`: islands → `Workspaces {}`, pill → `PillDots {}`
  - `clock`: islands → `Clock {}`, pill → `Clock { revealDate: false }`
  - `media`: islands → `MediaCell {}`, pill → `PillMusic {}`
  - `chip`: pill → `PillChip {}`
  - others map 1:1 to `Bandwidth`/`ControlPanelButton`/`WeatherButton`/`ResourceMonitor`/`Battery`/`Brightness`/`Volume`/`NetworkWidget`/`Tray` (create a thin `BandwidthText.qml` wrapper for the 4-`Text` speed readout if the existing `Bandwidth.qml` widget's popup behaviour is undesirable inside the centre cell).
  - If a module-resolution cycle appears (`qs.services` ↔ `qs.widgets.bar`), keep the registry in its own module (e.g. `qs.barmodel`) or switch `component()` to return `source` URL strings; the `catalog`/`allowed`/`layout` API is unchanged either way.

- [ ] **Step 3: Extract `MediaCell.qml`** from `DefaultBar.playerPill` (the `Rectangle` + `MprisWidget` + `MouseArea` block), binding its gate to `BarWidgets.firstPlayable`.

- [ ] **Step 4: Verify**
Run: `qmllint services/BarWidgets.qml widgets/bar/MediaCell.qml`
Expected: PASS.
Run the reload + log grep from Task 1 Step 5.
Expected: no matches. (Pins Review Focus #2 and #5 by construction; add a one-off check: temporarily add `"bogus"` to `Settings.barLayoutIslands.left`, reload, confirm it does not render and no error, then revert.)

---

### Task 3: Refactor the islands bar onto the model

**Files:**
- Modify: `widgets/bar/DefaultBar.qml`

**Interfaces:**
- Consumes: `BarWidgets.layout/style`, `BarWidgets.component`, `Settings.barLayoutIslands`, `MediaCell`.
- Produces: an islands bar whose zone membership/order comes from the model; identical default rendering.

- [ ] **Step 1:** Replace the hard-coded `leftZone` children with `Repeater { model: BarWidgets.layout("islands","left") }` + `Loader { sourceComponent: BarWidgets.component(modelData,"islands","left") ; Layout.fillWidth: true }` inside the existing `RowLayout`.

- [ ] **Step 2:** Replace `rightZone`/`utilities` children with a `Row` + `Repeater`/`Loader` over `("islands","right")`; media now resolves to `MediaCell`.

- [ ] **Step 3:** In `centerPill`/`centerRow`, drive children from `BarWidgets.layout("islands","center")`, preserving the equal-width end cells (`sideCellWidth = Math.max(firstChildWidth, lastChildWidth)`), so the default `bandwidth|control|clock` renders exactly as before.

- [ ] **Step 4:** Drive the bottom strip from `BarWidgets.layout("islands","bottom")` (default `[workspaces]`); width stays `topRow.implicitWidth`.

- [ ] **Step 5: Verify**
Run: `qmllint widgets/bar/DefaultBar.qml` → PASS.
Reload + log grep → clean.
Live: with `barStyle = "islands"`, confirm the bar looks identical to before (same order, same centre control alignment). **Pins Review Focus #1 and #3**: set `Settings.barLayoutIslands.left = []` via the editor (Task 5) and confirm an empty left zone renders without errors.

---

### Task 4: Refactor the pill bar onto the model

**Files:**
- Modify: `widgets/bar/pill/PillBar.qml`

**Interfaces:**
- Consumes: `BarWidgets.layout/component`, `Settings.barLayoutPill`.

- [ ] **Step 1:** `restContent` — replace `PillDots/Clock/PillChip` with a `Row` + `Repeater`/`Loader` over `("pill","rest")`; keep `spacing: 14`, the two-phase opacity, and `enabled`.

- [ ] **Step 2:** `openContent` core row — replace the top `RowLayout` children with `Repeater`/`Loader` over `("pill","core")` (`Layout.alignment: Qt.AlignVCenter`). Keep the divider and the detail `RowLayout` driven from `("pill","detail")`.

- [ ] **Step 3:** Keep media-only behaviour: `bandwidth` stays hidden while `BarWidgets.firstPlayable !== null` (bind `visible` on the loaded item; `PillMusic`/`MediaCell` are their own gate).

- [ ] **Step 4: Verify**
Run: `qmllint widgets/bar/pill/PillBar.qml` → PASS.
Reload + log grep → clean.
Live: `barStyle = "pill"` — expanded face looks identical; **Review Focus #1/#5** — set `pill.detail = []`, reload, confirm an empty detail row (no artefacts, no errors) and that with no player nothing errors.

---

### Task 5: Settings UI split + editor entry points

**Files:**
- Modify: `widgets/leftPanel/SettingsWidget.qml` (Bar card ~lines 125-519)

**Interfaces:**
- Consumes: `Settings.barIslandsDetached`; will call `BarEditState.begin(style)` (Task 6).
- Produces: four sub-sections inside the Bar card.

- [ ] **Step 1:** Split the Bar card into labelled sub-groups using the existing card/`RowLayout`/`AppComboBox`/`AppCheckBox`/`AppSpinBox` vocabulary: **Bar·General** (Orientation, Lock Bar, Always Expanded, Reveal-In Pressure, Reveal-Out Pressure), **Bar·Islands** (`visible: Settings.barStyle === "islands"`; `Detached` `AppCheckBox` → `Settings.barIslandsDetached`; an "Edit layout" control — a small `Rectangle` + `Label` + `MouseArea` styled with `Theme.accent`/`Theme.surfaceHover`, or a shared button component if the panel has one), **Bar·Pill** (`visible: Settings.barStyle === "pill"`; the same "Edit layout" control), **Frame** (existing `frame*` rows gated on `Settings.shellFrame`), plus the existing **Bar Style** selector.

- [ ] **Step 2:** Wire each "Edit layout" button to `BarEditState.begin(Settings.barStyle)` (Task 6).

- [ ] **Step 3: Verify**
Run: `qmllint widgets/leftPanel/SettingsWidget.qml` → PASS.
Reload. Open the left settings panel; toggle Bar Style and confirm the islands/pill sub-sections show/hide correctly; toggle `Detached` and confirm `settings.json` gains `bar.islands.detached`.

---

### Task 6: Edit-mode state service

**Files:**
- Create: `services/BarEditState.qml`
- Modify: `services/qmldir`

**Interfaces:**
- Produces `BarEditState` (singleton):
  - `property bool active`
  - `property string style` (`"islands"`/`"pill"`)
  - `function begin(style: string)`, `function end()`
  - `property string draggingId` (widget id or `""`), `property string dragFromZone`
  - `function place(id: string, zone: string, index: int)` → mutates `Settings.barLayout*` via `Settings.updateSetting`, dedupes, persists
  - `function remove(id: string, zone: string)`
- Consumed by: Tasks 5, 7, 8, 9.

- [ ] **Step 1:** Implement the singleton. `place()`/`remove()` read the current array, splice, write back with `Settings.updateSetting("bar.layout.islands"|"bar.layout.pill", obj)`. `end()` clears drag state.

- [ ] **Step 2: Verify:** `qmllint services/BarEditState.qml` → PASS; reload + grep → clean.

---

### Task 7: Edit overlay, tray, and in-bar drag

**Files:**
- Create: `widgets/bar/BarEditOverlay.qml`
- Modify: `widgets/bar/DefaultBar.qml`, `widgets/bar/pill/PillBar.qml` (dashed zones + drop targets when `BarEditState.active`), `widgets/bar/Bar.qml` (mount overlay; suppress auto-hide/hover-expand while editing)

**Interfaces:**
- Consumes: `BarEditState`, `BarWidgets.catalog`, `BarWidgets.allowed`, `Settings.barLayout*`.

- [ ] **Step 1:** `BarEditOverlay.qml` — dashed outline per zone (allowed high-light green, disallowed dim), a widget **tray** row listing catalog ids not placed in the active style (each an `icon`+`label` chip), and a `Done` button calling `BarEditState.end()`.

- [ ] **Step 2:** In-window floating-proxy drag: `MouseArea` per tray chip and per placed widget starts a drag; a floating `Item` follows the cursor; on release, hit-test the zone under the pointer — tray→zone = `place(id, zone, index)`, zone→zone = move, zone→tray or `Esc` = `remove`. Reject drops on `!allowed(id, style, zone)` (chip shakes / snaps back). `index` derives from the drop x relative to the zone's children.

- [ ] **Step 3:** In `Bar.qml`, when `BarEditState.active`: force the bar visible/locked open (suppress hover-expand + auto-hide), and mount `BarEditOverlay` above the content. On pill style, stack `rest`/`core`/`detail` so all three are visible drop targets.

- [ ] **Step 4: Verify**
Run: `qmllint` on all touched files → PASS.
Reload + log grep → clean.
Live: enter edit mode from the Settings button; drag `weather` from islands `left` to `right`; confirm it moves, persists, and no error. Drag a widget to a disallowed zone → rejected. Drag a placed widget to the tray → removed. Press `Done`; reload the bar and confirm the layout survived. **Pins Review Focus #4** (unresolved positions handled in Task 8).

---

### Task 8: Detached islands surface

**Files:**
- Create: `widgets/bar/DetachedBar.qml`
- Modify: `widgets/bar/Bar.qml`

**Interfaces:**
- Consumes: `Settings.barIslandsDetached`, `Settings.barIslandsPos`, `BarWidgets.layout/component`.
- Produces: when `barStyle === "islands" && barIslandsDetached`, the main bar hides its single surface and `DetachedBar` renders one rounded pill per section (`left/center/right/bottom`), each `Repeater`ing its model zone.

- [ ] **Step 1:** `DetachedBar.qml` — a full-output transparent layer `PanelWindow` with `mask` = union of the four pill rects (so only pills are interactive and the desktop between them stays clickable). Each pill: `Rectangle` chrome (`Theme.surface`, `Theme.radius`, `Theme.barContentHeight`) sized to `BarWidgets.layout("islands",section)` content, positioned from `barIslandsPos[section]`; when `x === -1`, resolve to the default anchor (left→screen-left, center→screen-centre, right→screen-right, bottom→screen-bottom-centre) so it never draws at `(-1,-1)`.

- [ ] **Step 2:** In `Bar.qml`, when detached: hide the main `pill`'s content (`DefaultBar`) and instantiate `DetachedBar`; otherwise current behaviour. Keep side islands/popups working.

- [ ] **Step 3: Verify**
Run: `qmllint` touched files → PASS.
Reload + log grep → clean.
Live: enable `Detached`; confirm four independent pills at sensible default positions and the desktop remains clickable between them. Toggle off → single bar returns unchanged. **Pins Review Focus #4.**

---

### Task 9: Detached drag + placement persistence

**Files:**
- Modify: `widgets/bar/DetachedBar.qml`, `widgets/bar/BarEditOverlay.qml`

**Interfaces:**
- Consumes: `BarEditState.active`.

- [ ] **Step 1:** In edit mode, make each detached pill draggable anywhere on screen; on release write `Settings.updateSetting("bar.islands.pos", {...x,y})` for that section (absolute top-left px). Widget-level drag inside a pill still uses Task 7's tray/zone rules.

- [ ] **Step 2: Verify**
Run: `qmllint` → PASS. Reload + log grep → clean.
Live: drag the `left` pill to the bottom-left, reload, confirm it stays; confirm `Esc`/`Done` exits without saving a half-drag.

---

### Task 10: Regression + defaults verification

**Files:** none (verification only).

- [ ] **Step 1:** Fresh state: temporarily move `settings.json` aside, reload; confirm both styles render the exact default layouts and the log is clean. Restore `settings.json`.
- [ ] **Step 2:** Hand-edit `settings.json` with an unknown id and a duplicate id in one zone; reload; confirm they are dropped (Review Focus #2/#3) and the bar renders.
- [ ] **Step 3:** Toggle orientation Top/Bottom for both styles and both detached states; confirm no errors and correct anchoring.
- [ ] **Step 3b:** With no player playing, confirm `media`, `chip`, and the spectrum are hidden and no errors. With a player playing, confirm `media`/`PillMusic` appears in its zone and the spectrum behaves.
- [ ] **Step 4:** Report results; do not commit.

---

## Out of scope (Stage 2)

Component **variants** (alternate looks/behaviours per widget) build on `BarWidgets.component()` in a later plan; nothing here should block adding a `variant` argument to that function later.
