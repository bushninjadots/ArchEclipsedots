# Bar Freeform Layout Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Enable freeform linear placement of bar components along top/bottom edges with N-body frame support and per-component frame shape/radii options, while preserving exact current layouts via migration.

**Architecture:** Replace zone-based layout arrays with per-edge linear sequences (`bar.layout.top`/`bottom`). Extend frame pipeline from fixed 3 bodies to arrays + count (max 64). Update editing to linear reorder/insert. Migrate existing zone layouts on load to reproduce visuals exactly. Keep catalog/component model; introduce allowed-by-edge in freeform mode.

**Tech Stack:** QML/QtQuick, QuickShell, GLSL (frame.frag), JSON settings persistence.

**Spec:** docs/superpowers/specs/2026-10-11-bar-freeform-layout-design.md

## Global Constraints
- Defaults MUST reproduce today’s layouts exactly (no regression to islands/pill).
- Do NOT commit unless the user explicitly asks.
- Preserve existing visual parity after migration.
- Maintain lint cleanliness (qmllint); reload log must show `Configuration Loaded` with no error patterns (`typeerror|referenceerror|invalid property|binding loop|is not defined|Cannot assign|Syntax error|Error|Failed to load`).
- Settings: arrays/objects stored raw in settings.json; scalars wrapped as `{value:...}`. Use `Settings.updateSetting(path,value)` for persistence.
- Frame shader must support up to N<=64 bodies dynamically (array + count). No breaking change to existing behavior when bodies count small.

## Review Focus
1. **Migration correctness** — when linear arrays missing, derive from current zone layout reproduces exact attached/detached visual positions for both styles.
2. **Linear ordering persistence** — reordering any single component persists to `bar.layout.top/bottom` via `updateSetting` and survives reload.
3. **Frame N-bodies** — bodiesList length/count matches visible cells; frame border tracks middle parts without artifacts when count changes.
4. **Editing semantics** — linear insert/reorder works without zone constraints; drop indicator placement correct; `BarEditState.end()` resets drag state.
5. **Backward compatibility** — existing configs (including user’s saved layouts and detached islands state) remain valid after migration and render correctly.

---

### Task 1: Extend Settings with linear layout keys + migration

**Files:**
- Modify: `theme/Settings.qml`

**Interfaces:**
- Consumes: Existing `barLayoutIslands`, `barLayoutPill`, `barIslandsDetached`, `barIslandsPos`, `barStyle`, `barOrientation`.
- Produces: `barLayoutTop` (array), `barLayoutBottom` (array), `barLayoutMode` (string). Migration logic `_migrateLinearLayouts()`; helpers `_deriveLinearFromZones(style, edge)`; public accessors remain compatible.

- [ ] **Step 1: Write failing test (conceptual)**  
  Define expected: on fresh load with no linear keys, `Settings.barLayoutTop`/`barLayoutBottom` become non-empty arrays derived from current style/orientation producing same visual order as zones. (Verification via reload + IPC geometry not a unit test; treat as integration check captured by Review Focus #1.)

- [ ] **Step 2: Add properties and defaults**  
  In `Settings.qml`, add `property var barLayoutTop: []`, `property var barLayoutBottom: []`, `property string barLayoutMode: "linear"`. Initialize as empty arrays (migration fills them).

- [ ] **Step 3: Add migration helpers**  
  Implement `_deriveLinearFromZones(style, edge)` returning string array:
  - islands, edge==top (barOrientation top): concatenate left + center + right zone arrays in that order (left-to-right).  
  - islands, edge==bottom: bottom zone array.  
  - pill, top: concatenate rest + core + detail in that order (preserves pill faces order).  
  - pill, bottom: [] (or bottom zone if present; pill has no bottom zone today).  
  Return deduped? preserve order as-is (drop unknown handled elsewhere). Handle empty zones.

- [ ] **Step 4: Implement migration logic**  
  Add `_migrateLinearLayouts()` called early in `Component.onCompleted()` (or after initial load). Conditions: if `barLayoutTop.length==0` OR `barLayoutBottom.length==0` (or `barLayoutMode` unset) derive for both edges using current `barStyle`/`barOrientation`; write via `updateSetting("bar.layout.top", barLayoutTop)` and `updateSetting("bar.layout.bottom", barLayoutBottom)`; set `barLayoutMode="linear"`.

- [ ] **Step 5: Add updateSetting aliases**  
  Ensure `persist()` writes `bar.layout.top`, `bar.layout.bottom`, `bar.layout.mode` (store raw arrays/strings). Add tolerant handling in `reload()` to read these keys if present.

- [ ] **Step 6: Verify**  
  Run `qmllint theme/Settings.qml`; reload bar; grep log for `Configuration Loaded` and no error patterns. Check settings.json has `bar.layout.top`/`bottom` present (derived).  
  Expected: clean, no regressions.

- [ ] **Step 7: Commit**  
  ```bash
  git add theme/Settings.qml
  git commit -m "feat(settings): add linear layout top/bottom with zone→linear migration"
  ```

---

### Task 2: Extend BarWidgets for edge-aware allowed/component

**Files:**
- Modify: `services/BarWidgets.qml`

**Interfaces:**
- Consumes: Existing catalog, layout/allowed by zone.
- Produces: `allowed(id, style, edgeOrZone)` overload-friendly (accept edge string "top"/"bottom" or existing zone); keep backward compatibility. `layoutLinear(style, edge)` returns string[] (uses Settings.barLayoutTop/Bottom or falls back to derived). Ensure component lookup unchanged.

- [ ] **Step 1: Add edge-aware allowed**  
  Add function `allowedByEdge(id, style, edge)` returning bool. Default allow (freeform): true for known ids in catalog; can restrict bottom to workspaces-only if desired to preserve islands semantics? But freeform means move anywhere; user wants unbounded. Keep permissive; rely on catalog validity. Maintain existing `allowed(id,style,zone)` for compatibility (if third param is zone name, preserve behavior).

- [ ] **Step 2: Add layoutLinear helper**  
  Add `function layoutLinear(style, edge) { ... }` that returns `Settings.barLayoutTop` if edge=="top", else `Settings.barLayoutBottom`. If empty, derive on-the-fly via `_deriveFromCurrent(style,edge)` (mirror Settings logic) to be safe before Settings migration runs? Or just read Settings values (Settings migrates on load).

- [ ] **Step 3: Keep component() unchanged**  
  No change to component factory; it already returns Component by (id,style,zone) — zone unused for rendering in freeform, but signature compatible.

- [ ] **Step 4: Verify**  
  `qmllint services/BarWidgets.qml`; reload; log clean.  
  Expected: PASS.

- [ ] **Step 5: Commit**  
  ```bash
  git add services/BarWidgets.qml
  git commit -m "feat(barwidgets): add edge-aware helpers for freeform linear layout"
  ```

---

### Task 3: Extend BarEditState for linear editing

**Files:**
- Modify: `services/BarEditState.qml`

**Interfaces:**
- Consumes: Settings, BarWidgets (linear arrays). 
- Produces: Linear drag state `dragId`, `dragIndex` (-1), `dropIndex` (-1), `axis="x"`, `edge="top"`. Methods `beginLinearDrag(id, index, edge, px,py)`, `moveLinear(px,py, maxX,maxY)`, `commitLinear()`, `linearLayout(edge)` (returns array copy), `setLinearLayout(edge, arr)`, `indexAtLinear(edge, px,py, cells)` (optional), `insertionIndex(edge, px, cells)`.

- [ ] **Step 1: Add properties**  
  Add `property string dragId: ""`, `property int dragIndex: -1`, `property int dropIndex: -1`, `property string axis: "x"`, `property string edge: "top"`.

- [ ] **Step 2: Reset in end()**  
  In `end()`, also reset `dragId=""`, `dragIndex=-1`, `dropIndex=-1`, `edge="top"`.

- [ ] **Step 3: Linear layout accessors**  
  `function linearLayout(edge) { return edge=="top" ? Settings.barLayoutTop.slice() : Settings.barLayoutBottom.slice() }`  
  `function setLinearLayout(edge, arr) { Settings.updateSetting(edge=="top"?"bar.layout.top":"bar.layout.bottom", arr.slice()) }`

- [ ] **Step 4: Begin/move/commit linear**  
  `beginLinearDrag(id, index, edge, px,py)`: set `active=true`, `style=Settings.barStyle`, `dragId=id`, `dragIndex=index`, `dropIndex=index`, `edge=edge`, `axis="x"`, record grab (store px,py if needed).  
  `moveLinear(px,py,maxX,maxY)`: compute insertion index based on px relative to cell positions (or between cells). Set `dropIndex = clamp(insertionIndex(...), 0, count)`.  
  `commitLinear()`: if `dragId=="" or dragIndex<0` return; let `arr = linearLayout(edge)`; remove element at `dragIndex` if present (handle if moved); compute insert index `di = dropIndex`; if removing before di, di--; insert `dragId` at di; `setLinearLayout(edge, arr)`; call `end()`.

- [ ] **Step 5: Insertion index helper**  
  Given list of cell rects in order `{x,y,w,h,id}` along edge, `insertionIndex(edge, px, cells)` returns index to insert before (0-based): for x, find smallest i with px < cells[i].x + cells[i].w/2; else cells.length. Clamp to [0,length].

- [ ] **Step 6: Verify**  
  `qmllint services/BarEditState.qml`; reload; log clean.  
  Expected: PASS.

- [ ] **Step 7: Commit**  
  ```bash
  git add services/BarEditState.qml
  git commit -m "feat(bareditstate): add linear drag/reorder state and persistence"
  ```

---

### Task 4: Frame pipeline — extend shader to N bodies (max 64)

**Files:**
- Modify: `widgets/frame/frame.frag`

**Interfaces:**
- Produces: uniform block with `int u.bodyCount`, `vec4 u.shape[64]`, `vec4 u.radii[64]`. Fragment loops 0..bodyCount-1 (clamp <64). Existing behavior unchanged when bodyCount==0/1/2/3.

- [ ] **Step 1: Update uniform block**  
  Replace fixed `shape0,radii0,shape1,radii1,shape2,radii2` with:
  ```glsl
  int u.bodyCount;
  vec4 u.shape[64];
  vec4 u.radii[64];
  ```
  (keep all other uniforms same; std140 layout fine.)

- [ ] **Step 2: Update fragment union loop**  
  Replace b0,b1,b2 computation with loop:
  ```glsl
  float united = frame;
  for (int i = 0; i < u.bodyCount && i < 64; i++) {
      float b = body(p, u.shape[i], u.radii[i]);
      if (b < FAR) {
          united = min(united, smoothUnion(frame, b - swell, k));
      }
  }
  ```
  (early-if keeps cheap; < FAR guard optional.)

- [ ] **Step 3: Verify compilation/load**  
  `qmllint` not applicable to frag; reload bar, grep log for `Configuration Loaded` and no shader/compile errors. Test with existing 3-body case (pill/left/right) — should behave identically.  
  Expected: clean.

- [ ] **Step 4: Commit**  
  ```bash
  git add widgets/frame/frame.frag
  git commit -m "feat(frame): extend shader to N bodies (array+count, max 64)"
  ```

---

### Task 5: FrameField — support bodiesList (N bodies)

**Files:**
- Modify: `widgets/frame/FrameField.qml`

**Interfaces:**
- Consumes: `property var bodies` (legacy {pill,left,right,on}) and/or `property var bodiesList: []` (array of rect-like objects: `{x,y,w,h,on,tl,tr,br,bl,radius,...}`).
- Produces: uploads `u.bodyCount`, fills `u.shape[i]`, `u.radii[i]` for i<min(count,64). Backward compatible with legacy `bodies` (if bodiesList empty, build from bodies).

- [ ] **Step 1: Add bodiesList property**  
  Add `property var bodiesList: []`

- [ ] **Step 2: Build arrays from bodiesList or fallback**  
  In fragmentShader uniforms/update, compute `var list = bodiesList; if (!list || list.length==0) { build legacy list from bodies.pill/left/right }`. Let `count = Math.min(list.length, 64)`.

- [ ] **Step 3: Fill shape and radii per element**  
  For each i< count: let r = list[i]; if (!r || r.on===false || r.w<=0 || r.h<=0): shape[i]=(0,0,1e-6,1e-6), radii[i]=(0,0,0,0); else shape[i] = `vec4(r.x+r.w/2, r.y+r.h/2, r.w/2, r.h/2)`; radii[i] from per-element (r.tl/tr/br/bl or r.radius or global) with topBar-aware logic preserved (mirror existing `radiiOf` behavior). Keep existing defaults when per-element missing.

- [ ] **Step 4: Upload u.bodyCount**  
  Set `u.bodyCount = count`.

- [ ] **Step 5: Verify**  
  `qmllint widgets/frame/FrameField.qml`; reload with existing frame bodies → identical visuals.  
  Expected: clean.

- [ ] **Step 6: Commit**  
  ```bash
  git add widgets/frame/FrameField.qml
  git commit -m "feat(frame): add bodiesList support with legacy fallback"
  ```

---

### Task 6: Bar — compute frameBodiesList from linear layout (freeform)

**Files:**
- Modify: `widgets/bar/Bar.qml`

**Interfaces:**
- Consumes: `Settings.barLayoutTop/Bottom`, `Settings.barStyle`, `Settings.barOrientation`, `layoutSurface` (current bar surface). Needs cell rects for rendered linear sequence.
- Produces: `readonly property var frameBodiesList: root._computeFrameBodiesList()`; pass to FrameField as `bodiesList: root.frameBodiesList`. Keep legacy `frameBodies` for compatibility? Or compute both; FrameField prefers bodiesList. Compute legacy from current zones if needed, but prefer bodiesList.

- [ ] **Step 1: Add _computeFrameBodiesList()**  
  Return array of body objects `{x,y,w,h,on,...}` for all visible cells in current rendered layout along active edge. Determine edge = `Settings.barOrientation == "top" ? "top" : "bottom"` (or follow bar orientation). Get linear sequence for edge from Settings/BarWidgets. For each id in sequence, find its rendered cell rect in scene coords (map from layoutSurface item to null/scene). Push `{x,y,w,h,on:true}` (use global/topBar radii defaults; per-component radii added later if needed).

- [ ] **Step 2: Update FrameField usage**  
  In Bar.qml, where FrameField is used (inside bar surface when ShellFrame.enabled), pass `bodiesList: root.frameBodiesList`. Also keep `bodies: root.frameBodies` if still referenced, but FrameField now prefers list.

- [ ] **Step 3: Ensure detached vs attached**  
  `layoutSurface` is `detached ? stripRoot.detachedBar : currentPageLoader.item`. Both must expose cell rects for their rendered linear sequence. (DetachedBar will be updated in Task 7.)

- [ ] **Step 4: Verify**  
  `qmllint widgets/bar/Bar.qml`; reload. With existing layouts, frame bodies count matches visible cells; visuals unchanged.  
  Expected: clean.

- [ ] **Step 5: Commit**  
  ```bash
  git add widgets/bar/Bar.qml
  git commit -m "feat(bar): compute frameBodiesList from linear layout"
  ```

---

### Task 7: Update DefaultBar to render linear sequence (top/bottom)

**Files:**
- Modify: `widgets/bar/DefaultBar.qml`

**Interfaces:**
- Consumes: Settings.barLayoutTop/Bottom, barOrientation, BarWidgets.
- Produces: Renders single Row per active edge from linear sequence; exposes `editCells()` returning cells for linear sequence; exposes `editZones()` as needed (or return single strip zone). Preserve existing sizing logic where possible.

- [ ] **Step 1: Add linear sequence access**  
  Add `readonly property string edge: Settings.barOrientation == "top" ? "top" : "bottom"`  
  `readonly property var linearIds: edge=="top" ? Settings.barLayoutTop : Settings.barLayoutBottom`

- [ ] **Step 2: Render linear Row**  
  Replace zone-based left/center/right/bottom structure with a single `Row { id: stripRow; anchors.fill: parent (or center aligned); spacing: Theme.spacing }` using `Repeater { model: linearIds; delegate: Loader { sourceComponent: BarWidgets.component(modelData,"islands",edge); anchors.verticalCenter: parent.verticalCenter } }`. Handle center alignment by anchoring stripRow to horizontal center when desired (islands top bar centered in typical layout)? Preserve visual parity with current topRow/centerRow by placing in migration order (migration gives left+center+right sequence) so visual positions match.

- [ ] **Step 3: Update editCells() for linear**  
  Rewrite `_collectCells`/`editCells()` to iterate `linearIds` and collect rects from stripRow’s children (each delegate item/Loader) via `mapToItem(null,0,0)`. Return array `{id,zone:edge,x,y,w,h}` (use edge as zone label).

- [ ] **Step 4: Update editZones()**  
  Return single zone rect for the strip `{zone:edge, x,y,w,h}` covering stripRow mapped to scene.

- [ ] **Step 5: Verify sizing (Loader rule)**  
  Ensure Loaders have NO explicit `width:` binding (auto-size). Center delegates: if needed, preserve naturalWidth equalization only where migration order matches old center ends? Migration order is left+center+right in sequence — old center ends used sideCellWidth equalization; in linear Row, equalizing ends means wrapping center items in width-equalized Items. But easier: for visual parity, when rendering islands in linear mode with migrated order (left, c1,c2,..., right), we can detect center segment by index positions matching migration? Or alternatively, during migration record positions? Simpler: keep the existing center-equalization logic by reconstructing the three groups conceptually from linearIds? Or just apply equalization for islands top edge by reusing the old centerRow.sideCellWidth calculation logic on the corresponding elements. But with linear Row it’s cleaner to not special-case — migration order is chosen to reproduce visuals; test against defaults.

- [ ] **Step 6: Verify**  
  `qmllint widgets/bar/DefaultBar.qml`; reload islands attached/detached defaults → geometry matches (Task 8-10 baselines).  
  Expected: clean.

- [ ] **Step 7: Commit**  
  ```bash
  git add widgets/bar/DefaultBar.qml
  git commit -m "feat(defaultbar): render islands via linear top/bottom sequence"
  ```

---

### Task 8: Update PillBar to render linear sequence (freeform)

**Files:**
- Modify: `widgets/bar/pill/PillBar.qml`

**Interfaces:**
- Consumes: Settings.barLayoutTop/Bottom (or per-face linear). For pill style, current faces are rest/core/detail (vertical/arrangement). Freeform: replace faces with single linear sequence along active edge? Or keep pill structure but allow linear per “track”? User wants freeform along bar edge; pill is a style. Map pill to linear top sequence (migration: rest+core+detail). Render as single horizontal track in linear/freeform mode.
- Produces: Linear rendering for pill; editCells/editZones updated for linear when active.

- [ ] **Step 1: Add linear access**  
  `readonly property string edge: Settings.barOrientation == "top" ? "top" : "bottom"`  
  `readonly property var linearIds: edge=="top" ? Settings.barLayoutTop : Settings.barLayoutBottom`

- [ ] **Step 2: Linear rendering path**  
  Add boolean `property bool freeformLinear: true` (pill uses linear). When freeformLinear, render single Row `restContent`/expanded/open paths replaced by linear strip? Or overlay: show linear Row in normal/expanded states (preserving pill background/expansion behavior where applicable). Keep existing hover/expansion machinery but drive content from linearIds. For simplicity: in freeform mode, normal state renders Repeater over linearIds in a single Row inside pill background.

- [ ] **Step 3: Edit face linear**  
  In editContent (when BarEditState.active), render edit rows from linearIds as single horizontal edit row (or per “logical” groups? but freeform is flat). For linear editing, show single Row of draggable cells representing linearIds in order, with drop indicators between them.

- [ ] **Step 4: Update editCells/editZones**  
  Return cells for linear sequence in edit face (or normal face cells when not editing? existing guards return [] if not active). Collect from the linear edit Row children.

- [ ] **Step 5: Verify**  
  `qmllint widgets/bar/pill/PillBar.qml`; reload pill style defaults (migration rest+core+detail) → visuals preserved; edit mode gives linear droppable strip.  
  Expected: clean.

- [ ] **Step 6: Commit**  
  ```bash
  git add widgets/bar/pill/PillBar.qml
  git commit -m "feat(pillbar): support linear freeform sequence rendering/editing"
  ```

---

### Task 9: DetachedBar — adapt to linear layout (or deprecate in freeform)

**Files:**
- Modify: `widgets/bar/DetachedBar.qml`

**Interfaces:**
- Consumes: Linear layout per section? Detached islands currently render four sections (left/center/right/bottom) as separate pills. With freeform edge-based, detached concept shifts. But requirement states “detached islands” exists (islands-only). Keep backward compatibility: when using islands style in linear mode, detached still renders the four logical groups as before? Or derive groups from linear sequence split (left/center/right/bottom positions)? Migration preserves groups. For now, keep DetachedBar reading zone-derived content or read from Settings.barLayoutIslands groups for islands style? To preserve exact behavior, DetachedBar can continue using `BarWidgets.layout("islands", section)` (zone-based) while attached uses linear; that maintains compatibility. No change required if we don’t break islands detached. Verify behavior unchanged.

- [ ] **Step 1: Review**  
  DetachedBar uses `BarWidgets.layout("islands", section)` for ids. Settings still has `barLayoutIslands` and detached pos. Migration doesn’t remove zone keys. Keep as-is unless regression found.

- [ ] **Step 2: Verify**  
  Reload islands+detached with defaults → geometry unchanged from baselines.  
  Expected: clean.

- [ ] **Step 3: Commit (no-op safe)**  
  ```bash
  git add widgets/bar/DetachedBar.qml 2>/dev/null || true
  git commit -m "chore(detachedbar): verify compatibility with linear layout (no functional change)" 2>/dev/null || true
  ```

---

### Task 10: BarEditOverlay — linear drag/reorder UI

**Files:**
- Modify: `widgets/bar/BarEditOverlay.qml`

**Interfaces:**
- Consumes: BarEditState linear methods, layoutSurface cell rects for current edge.
- Produces: Linear insertion drop indicator; on drag, call `beginLinearDrag/moveLinear/commitLinear`. In linear/freeform mode, ignore zone-based hit-testing.

- [ ] **Step 1: Detect mode**  
  Determine if linear/freeform active (BarEditState.style set; use linear mode). Prefer linear when Settings.barLayoutMode=="linear".

- [ ] **Step 2: Linear hit-testing**  
  When in linear mode, collect cells for current edge from layoutSurface.editCells() (updated to return linear). On pressed: find which cell hit → call `BarEditState.beginLinearDrag(cell.id, index, edge, mouse.x,mouse.y)`. On positionChanged: if dragging linear, compute insertion index from mouse.x and cell list → `BarEditState.moveLinear(...)` and draw vertical drop line between cells at dropIndex. On released: `BarEditState.commitLinear()`.

- [ ] **Step 3: Drop indicator**  
  Draw rectangle/line at insertion point (between cells[di-1] and cells[di]) in overlay coordinates.

- [ ] **Step 4: Fallback to zone mode**  
  If not linear mode, preserve existing zone-based logic (for backward compat).

- [ ] **Step 5: Verify**  
  `qmllint widgets/bar/BarEditOverlay.qml`; edit mode islands/pill → linear reorder works, drop indicator appears, positions persist.  
  Expected: clean.

- [ ] **Step 6: Commit**  
  ```bash
  git add widgets/bar/BarEditOverlay.qml
  git commit -m "feat(bareditoverlay): linear drag/reorder with insertion indicator"
  ```

---

### Task 11: Integration verification & regression

**Files:**
- Verify: All modified above + settings.json state.

- [ ] **Step 1: Lint all modified**  
  `qmllint theme/Settings.qml services/BarWidgets.qml services/BarEditState.qml widgets/frame/FrameField.qml widgets/bar/Bar.qml widgets/bar/DefaultBar.qml widgets/bar/pill/PillBar.qml widgets/bar/DetachedBar.qml widgets/bar/BarEditOverlay.qml widgets/frame/frame.frag` (frag skipped by qmllint). All QML exit 0 or 255-no-output (pass).

- [ ] **Step 2: Reload and log grep**  
  `~/.config/hypr/scripts/bar.sh >/dev/null 2>&1 & sleep 4; grep -c "Configuration Loaded" /tmp/qs-bar-bender.log; grep -E "typeerror|referenceerror|invalid property|binding loop|is not defined|Cannot assign|Syntax error|Error|Failed to load" /tmp/qs-bar-bender.log`

- [ ] **Step 3: Defaults regression (islands attached)**  
  Verify geometry matches pre-freeform islands attached defaults (left/center/right/bottom positions and cell widths). Via IPC diag if available; otherwise compare to recorded baselines.

- [ ] **Step 4: Defaults regression (islands detached)**  
  Verify detached pills positions/cells unchanged.

- [ ] **Step 5: Pill defaults regression**  
  Verify pill linear sequence reproduces rest+core+detail order visually.

- [ ] **Step 6: Edit/reorder persistence**  
  In edit mode, move a component; commit; reload → order persists in settings.json `bar.layout.top/bottom`.

- [ ] **Step 7: Frame bodies count**  
  With N visible cells, frameBodiesList.length == number of visible cells; shader u.bodyCount matches.

- [ ] **Step 8: Restore user settings**  
  Restore original user layout (style=pill, detached=true, islands/pill layouts and pos per preserved state) and verify ok.

- [ ] **Step 9: Clean temp probes**  
  Ensure no temporary IPC diagnostics remain (services/Ipc.qml clean).

- [ ] **Step 10: Commit**  
  ```bash
  git add -A
  git commit -m "feat: bar freeform linear layout + N-body frame" 2>&1 | tail -2
  ```

---

**Global verification:** After all tasks, full reload clean; defaults preserved; migration correct; editing/persistence works; frame tracks N bodies. No commits made unless explicitly requested (constraint maintained throughout).
