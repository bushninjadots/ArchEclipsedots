# GitHub Contributions Heatmap — Full-Year Graph Upgrade — Design

- Date: 2026-10-10
- Status: Approved (design), pending written-spec review
- Scope of work: `desktop-widgets` Quickshell project (`~/.config/desktop-widgets`)

## 1. Summary

Upgrade the existing desktop **GitHub contributions heatmap** widget from a compact
fixed 12-week grid into a full-featured, GitHub-style contributions graph with a
hover-revealed toolbar, month/weekday labels, a year selector, a hover tooltip,
subtle animation, streak/busiest-day stats, and click-a-day detail. The look must
match the existing desktop widgets (clock, music, lyrics): translucent backing,
accent-tinted, same typography and rounded corners.

The current compact 12-week layout is **preserved** as the "vertical" design mode.

## 2. Goals / Non-goals

### Goals
- Full calendar-year graph, GitHub-style: weeks as columns, days as rows (Mon-aligned).
- Month labels above the grid; weekday labels at the left.
- Year selector to view any year the API exposes.
- Hover tooltip showing the date and that day's contribution count.
- Click a day to pin it and show its detail in the toolbar.
- Streak (longest) and busiest-day statistics for the selected year.
- Subtle animation: fade-in on data load; hovered cell highlight.
- Toolbar revealed on hover, overlaid so it does not shift layout.
- Visual style consistent with existing Eclipse desktop widgets.

### Non-goals
- No changes to the main bar (`~/.config/quickshell/archeclipse`).
- No HTML-scraping fallback (the public jogruber API is sufficient).
- No multi-user or multi-repo breakdown.
- No new dependencies.

## 3. Approved decisions

| Decision | Choice |
|---|---|
| Target scope | Full GitHub-style graph (full year, scrollable, month labels, year selector, toolbar, hover tooltip, animated ramp) |
| Controls surface | Hover-reveal toolbar |
| Visual treatment | Match existing Eclipse widgets |
| Extras (all) | Month labels, hover tooltip, subtle animation, streak & stats, weekday labels, click-a-day detail |
| Structure | Extend in place; split graph/toolbar out; keep vertical = compact 12-week mode |

## 4. Architecture

```
HeatmapWidget.qml  (orchestrator: backing box, style, Config+service wiring, hover state)
├── HeatmapToolbar.qml   (hover-revealed: username edit, ‹ year ›, refresh, stats line)
├── HeatmapGraph.qml     (the graph: month labels, weekday labels, cells, tooltip, pin, animation)
└── (vertical mode)      compact 12-week rendering, unchanged behavior
```

Data flow:

```
Config.heatmapUsername / heatmapYear / heatmapDesign
        │
        ▼
GithubContrib (singleton service)  ──python3 -I──►  bin/github-contributions
  year, years, data, total, loading, error
        │
        ▼
HeatmapWidget → HeatmapGraph.cells  →  cells / tooltip / stats
```

The service is the single source of truth for contribution data; the widget only
derives presentation (cell layout, colors, stats) from it.

## 5. Data layer

### 5.1 `bin/github-contributions`
- Keep current no-arg behavior: current year, cache-first, 24h cache.
- Add `--year YYYY`: fetch that specific year (via `?y=YYYY`), cache to
  `{user}_{YYYY}.json`, print `{contributions, total, user, year}`.
- Add `--years`: from the bare endpoint `GET /v4/{user}`, return
  `{"user": <u>, "years": [<sorted int years>]}` using the keys of the `total`
  map. Cache briefly (e.g. reuse the 24h cache policy under a
  `{user}_years.json` file) to avoid extra requests.
- `--force`/`-f` continues to bypass the cache for the requested fetch.
- `parse_args()` extended to `(user, year, years_only, force)`.
- Normalization (`normalize_user`) unchanged.

### 5.2 `GithubContrib` service
- New state: `year` (int, selected), `years` (list of int), `total` for the
  selected year, plus existing `data`/`loading`/`error`/`user`.
- New: `setYear(y)` → refetch for that year via `--year`.
- `setUser(u)` → also refresh `years` (fetch `--years`).
- `refresh()` fetches the selected year; `forceRefresh()` passes `--force`.
- On completion of a `--years` fetch, populate `years`; if the selected `year`
  is not in the list, fall back to the latest available year.
- Poll timer (existing) keeps refreshing the selected year.

### 5.3 Auxiliary stats (computed in QML)
Derived from the selected year's `data`:
- `longestStreak`: max run of consecutive days with `count > 0`.
- `busiestDay`: max `count` and its date.
- `total`: from the service (already provided).

## 6. Layout and visuals

### 6.1 Horizontal (full-year) — default full mode
- Monday-aligned grid: 53 week-columns × 7 day-rows.
- Cell size reuse: base ~11px + 2px gap (existing `heatmapScale` applies).
  Approx grid footprint at scale 1: ~660×90px, plus labels.
- Month labels row above the grid, positioned at the first week-column of each
  month (abbreviated, e.g. "Jul").
- Weekday labels column at the left for Mon / Wed / Fri.
- Color ramp: keep the existing 5-stop ramp (`#c8d8c8 → #9adb7d → #6fbf4a →
  #3d8f24 → baseCol`), `baseCol` = `inkColorA` (accent) or `#1a6b0f`. `heatmapColor`
  / `heatmapGradient` continue to influence it.
- Empty/future cells: transparent.

### 6.2 Vertical (compact 12-week) — unchanged
- Existing 7-across × 12-down grid, no month/weekday labels, no toolbar stats.
- Selected via `heatmapDesign === "vertical"`.

### 6.3 Backing / chrome
- Translucent rounded rectangle matching other widgets; padding to fit the
  header + graph + labels; height derives from content (not a fixed constant).

## 7. Interaction

- **Hover widget** → toolbar fades in at the top edge (overlaid; `opacity`
  animation). Fades out on leave.
- **Hover cell** → tooltip fades in near the cell: e.g.
  `Mon, Jul 14, 2026 · 12 contributions`; hovered cell lifts/highlights.
- **Click cell** → pins the day; toolbar shows the pinned day's date + count;
  pinned cell keeps a highlight ring. Click elsewhere / same cell to unpin.
- **Right-click** → existing `WidgetMenu` (Sync now, Design) unchanged;
  `forceRefresh()` still forces a cache-bypassing fetch for the selected year.
- **Year selector** (toolbar `‹ 2026 ›`) → `setYear`; grid re-renders with a
  brief fade.
- **Username edit** (toolbar) → existing edit flow (`cleanUser` + `Config.set` +
  `setUser`).

## 8. Settings / Hub

- `Config`: add `heatmapYear` (int; default = current year).
- Hub **persistence whitelist** (`WidgetsPage.qml` `keys`) and adapter/factory
  defaults: add `heatmapYear` (int, default current year). This is required so a
  Hub save does not drop the key.
- The **toolbar is the primary year selector**. A Hub schema row is optional;
  if added it uses the existing numeric `step` control
  (`"ctl": "step", "lo": 2008, "hi": <current year>`), matching
  `heatmapScale`/`heatmapX`/`heatmapY`. No dynamic-control plumbing is required,
  since the toolbar drives `heatmapYear` at runtime.
- Hub `HeatmapPreview.qml`: mirror the new graph (month labels; year from
  `draft.heatmapYear`; hover optional in the small preview).
- `heatmapDesign` semantics: `horizontal` = full-year graph; `vertical` =
  compact 12-week; `auto` resolves to horizontal (full-year). Existing value
  `"vertical"` continues to mean compact.

## 9. Testing / verification

- `python3 -m py_compile bin/github-contributions`.
- Script checks: `--year 2025` produces `{user}_2025.json` and a 365-day payload;
  `--years` returns the available-year list (expect the year map keys for
  `bushninjadots`, i.e. includes 2025 and 2026); `--force` still bypasses cache;
  no literal `${XDG_CACHE_HOME...}` directories are created.
- Instrumented `qs -p ~/.config/desktop-widgets` run + `qs -p ... log`: no
  `.qml[...]` / `TypeError` / `ReferenceError` / `Unable to assign` errors
  (only the pre-existing `PluginWidgetMenu.qml:54 Duplicate signal name`
  warning and unrelated socket warnings). Probe `console.log`s removed before
  finishing.
- Confirm horizontal places weeks across and days down, and vertical the
  mirror (as established in the orientation fix).
- Final **visual** confirmation by the user.

## 10. Files touched

- `bin/github-contributions` — `--year`, `--years`.
- `qml/shell/services/GithubContrib.qml` — `year`, `years`, `setYear`.
- `qml/shell/modules/desktop/heatmap/HeatmapWidget.qml` — orchestrator.
- `qml/shell/modules/desktop/heatmap/HeatmapGraph.qml` — new.
- `qml/shell/modules/desktop/heatmap/HeatmapToolbar.qml` — new.
- `qml/shell/modules/desktop/Singletons/Config.qml` — `heatmapYear`.
- `qml/shell/modules/desktop/WidgetMenu.qml` — keep Sync now / Design working.
- `qml/hub/HeatmapPreview.qml` — match new graph.
- `qml/hub/pages/WidgetsPage.qml` — whitelist `heatmapYear`.
- `qml/hub/schema/WidgetsPage.js` — schema row for `heatmapYear`.

## 11. Risks / notes

- Graph width (~660px) is larger than the current 320px box; the free-positioned
  anchor (`heatmapX/Y`) may need adjusting when switching to horizontal. Vertical
  mode remains compact.
- Per-year fetch uses the API's `?y=` parameter; the year list comes from the bare
  endpoint's `total` map, which reflects only GitHub-reachable years.
- Per `AGENTS.md`, no commits/pushes. The existing `heatmapColor` may currently
  resolve to the accent value; the ramp behavior is preserved.
- Preserve all prior fixes: `stops` as `var` (not `color`), `required property
  var modelData` on Repeater delegates, orientation-aware x/y mapping,
  `grid.cw` usage, username URL normalization.
