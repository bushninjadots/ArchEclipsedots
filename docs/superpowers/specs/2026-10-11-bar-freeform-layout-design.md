# Bar Freeform Layout System Design
Date: 2026-10-11
Status: Draft (approved)

## Intent & Success Criteria
- Allow moving any single component anywhere along bar edges (top/bottom). No fixed zones (left/center/right/bottom, rest/core/detail).
- Frame border must update/move around features (middle parts). Support per-component frame shape/radii option (on any/all).
- Unbounded placement along edges (linear left-to-right). 
- Preserve exact visual parity of current layouts on first migration (defaults reproduce today’s layouts). No regression.
- Drag-to-place editing remains; editing becomes linear reorder/insert.

## Constraints (from codebase)
- frame.frag hardcodes exactly 3 bodies (shape0/radii0..shape2/radii2). Must extend to N.
- FrameField.qml uploads only up to 3 bodies.
- Bar.qml frameBodies = {pill,left,right}.
- Layout model is zone-based (BarWidgets.layout per zone). 
- QuickShell/Qt ShaderEffect uniforms std140-fixed; use array + count with reasonable max (e.g. 64). "Unbounded" = bounded by safe max (bar has < 32 items typically).

## Approaches (chosen)
Approach 1: Freeform linear sequence (per edge). Replace zone arrays with `bar.layout.top` / `bar.layout.bottom` (ordered left-to-right). Migrate from zones on load to preserve visuals.

## 1) Layout Model
- New keys: `bar.layout.top` (string[]), `bar.layout.bottom` (string[]). Order = left-to-right along edge.
- `bar.layout.mode = "linear"` (default after migration). Keep zone keys during transition if needed.
- Settings (`theme/Settings.qml`): add props `barLayoutTop`, `barLayoutBottom`; persistence via `Settings.updateSetting("bar.layout.top", ...)` etc., consistent with existing format (arrays stored raw).
- Migration on load: if linear arrays missing/empty for current edge context, derive from current zone layout (islands: left row + center row + right row in that order for top; bottom row for bottom; pill: rest+core+detail sequence preserving order) to reproduce exact visuals.
- BarWidgets: keep catalog/component/allowed; `allowed(id, style, edge)` replaces zone-based gating in freeform mode (broad to allow moving anywhere).

## 2) Rendering
- DefaultBar.qml (islands): render single Row along active edge using Repeater over linear sequence for that edge. Remove left/center/right/bottom zone splits. Centering achieved by placing items in desired order (or by anchoring strip; defaults must match current visuals via migration).
- PillBar.qml: render linear sequence per relevant face/edge; maintain pill visuals where applicable. 
- DetachedBar.qml: concept evolves under freeform; may be replaced/repurposed (user wants edge-based freeform; detached islands behavior adjusted accordingly).

## 3) Editing (linear drag/reorder)
- BarEditState.qml: `dragId`, `dragIndex`, `dropIndex`, axis x. Hit-test cells in linear sequence; detect insertion between cells. 
- BarEditOverlay.qml: draw drop indicator between items; drag any component to any position (reorder/insert). Remove zone drop zones in linear mode.
- Commit moves reorder the linear array and persist.

## 4) Frame bodies (N, dynamic)
- frame.frag: replace 3 fixed bodies with arrays + count:
  - `int u.bodyCount; vec4 u.shape[64]; vec4 u.radii[64];` (shape center.xy,half.xy; radii tl,tr,br,bl)
  - loop up to bodyCount and <64: compute body + smoothUnion with existing k/swell.
- FrameField.qml: `property var bodiesList: []`; build arrays of length `min(bodiesList.length,64)`, set shape/radii per entry; upload `u.bodyCount`.
- Bar.qml: compute `frameBodiesList` = array of visible component body rects along edge(s) (all visible cells in rendered layout) in scene coords; pass to FrameField. Include pill/background body if needed (existing pill body can remain as element or be folded into list).
- Per-component shape/radii: support per-component frame config (shape, radii/corner radii, radius scale). Store via catalog defaults + optional per-placement overrides in layout entries (e.g. `{id, shape:"pill", radius:10,...}`) — keep simple first (catalog defaults) with room to extend.

## 5) Backward compatibility & migration
- On load: detect missing `bar.layout.top/bottom`. If absent, derive from active style’s zone layout to reproduce current visuals exactly.
- Keep existing keys during transition; write linear arrays going forward.
- Defaults must reproduce today’s layouts (Task 1-10 requirement).

## 6) Verification
- qmllint clean; reload log grep `Configuration Loaded`, no error-patterns.
- Geometry probes (IPC) verify bodiesList/count matches visible cells; frame updates on moves.
- Regression: all prior configs still render correctly after migration.

## Open questions (from design)
1. Centering in freeform: allow true freeform (recommended). Current islands center group preserved via migration order.
2. Per-placement vs per-widget radii: start with per-widget catalog defaults; extend to per-placement later if needed.
3. Max N: 64 sufficient.
4. Bottom edge: linear left-to-right (yes).

All approved. No visual companion needed for text design.
