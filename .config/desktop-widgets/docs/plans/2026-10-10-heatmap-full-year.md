# GitHub Heatmap Full-Year Graph — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Upgrade the desktop GitHub contributions heatmap widget from a compact 12-week grid into a full-year GitHub-style graph with a hover-revealed toolbar, month/weekday labels, a year selector, a hover tooltip, subtle animation, and streak/busiest-day stats.

**Architecture:** Keep `HeatmapWidget.qml` as the orchestrator; extract the full-year graph into a new `HeatmapGraph.qml` and the controls into a new `HeatmapToolbar.qml`. The existing compact 12-week rendering stays inline in `HeatmapWidget.qml` for `heatmapDesign === "vertical"`. The `GithubContrib` singleton remains the single source of truth (now year-aware), fed by `python3 -I bin/github-contributions`.

**Tech Stack:** Quickshell (Qt6 QML), Python 3 stdlib, the public `github-contributions-api.jogruber.de/v4` API.

**Spec:** `docs/specs/2026-10-10-heatmap-full-year-design.md`

## Global Constraints

- Working dir: `/home/bender/.config/desktop-widgets`.
- **Do NOT commit or push anything** (per `~/.config/hypr/AGENTS.md`): skip/ignore every `git commit` step; leave changes uncommitted.
- Never run maintenance `update.py`/`install.py`.
- Preserve all prior fixes: `stops` is `var` (never `color`); every Repeater delegate declares `required property int index` and `required property var modelData`; orientation-aware `x`/`y` mapping; grid cell height uses `grid`/`root` (never a bare `cw`); username is normalized (`cleanUser` in QML, `normalize_user` in Python) so URLs/handles become a bare login.
- Run QML manually only with `QML_IMPORT_PATH=/home/bender/.config/desktop-widgets/qml`.
- No new dependencies.
- `heatmapDesign` semantics: `horizontal` and `auto` = full-year graph; `vertical` = compact 12-week (unchanged).
- Widget look must match the existing widgets: translucent rounded backing, accent-tinted, Inter font, same radii.

## Review Focus

- **Zero-contribution year (e.g. 2025 has 1):** level computation must not divide by a zero peak → no `NaN`/`Infinity`; every cell stays `level 0`.
- **Empty/loading feed:** graph renders with `contributions: []` and hover tooltip on an empty cell shows "0 contributions" without a `TypeError`.
- **Calendar edges:** the year's first/last partial week and any future dates render as transparent cells; week count is 53 columns and must not throw for a Jan-1 year start or a leap year (366 days).
- **Rapid year stepping:** pressing `‹`/`›` repeatedly while a fetch runs must coalesce (no process-spawn errors, no stuck `loading`).
- **No username:** toolbar shows the edit affordance, graph is empty, and the stat line does not show a bogus streak/busiest value.

---

## Task 1: Fetcher `--year` / `--years`

**Files:**
- Modify: `bin/github-contributions`

**Interfaces:**
- Consumes: existing helpers `get`, `cache_path`, `load_cache`, `save_cache`, `normalize_user`, `resolve_user`, `fetch_contributions`, `get_current_year`.
- Produces CLI: `github-contributions [USERNAME] [--year YYYY] [--years] [--force]`.
  - `--years` → stdout `{"user": <str>, "years": [<int>... sorted ascending]}` (cached at `{user}_years.json`, 24h).
  - `--year YYYY` (or no `--year`) → stdout `{"contributions":[{date,count}], "total": <int>, "user": <str>, "year": <int>}` (cached at `{user}_{year}.json`).
  - `parse_args()` returns `(user, year, years_only, force)`.

- [ ] **Step 1: Extend `parse_args()`**

Return a 4-tuple. Scan `sys.argv[1:]`: `-f`/`--force` → `force=True`; `--years` → `years_only=True`; `--year` → next token sets `year` as int (skip it); any other non-flag token, if `user is None`, sets `user`. Keep flags working before or after the username.

- [ ] **Step 2: Add `fetch_years(username)`**

`GET {API_BASE}/{quote(username)}` (no query). The response's `total` is a dict keyed by year. Return `sorted(int(k) for k in data["total"])` when `total` is a dict, else `[]`. On any of the existing error conditions (`HTTPError` 404/429/other, `URLError`, `OSError`, `TimeoutError`, generic) return `[]` and let the caller emit the error JSON.

- [ ] **Step 3: Add a years-only branch in `main()`**

After resolving `username`: if `years_only`, try cache `{user}_years.json` unless `force`; else fetch; on success `save_cache(username, "years", {"years": [...], "user": username})` (reuse `cache_path(user, "years")`) and print `{"user": username, "years": [...]}`; on failure print `{"user": username, "years": [], "error": "..."}`. `return` (do not fall through).

- [ ] **Step 4: Honor `--year` in the normal branch**

`year = year_arg if year_arg is not None else get_current_year()`. Everything else (cache-first unless `force`, `fetch_contributions(username, year)`, normalization, `save_cache`) already works because it is already parameterized by `year`. Update the module docstring/usage line to document `--year` and `--years`.

- [ ] **Step 5: Verify**

Run:
```bash
cd /home/bender/.config/desktop-widgets
python3 -m py_compile bin/github-contributions && echo OK
python3 -I bin/github-contributions bushninjadots --years
python3 -I bin/github-contributions bushninjadots --year 2025 | python3 -c "import sys,json;d=json.load(sys.stdin);print(d['year'],len(d['contributions']),d['total'])"
ls ~/.cache/desktop-widgets/github/
```
Expected: `OK`; the `--years` output includes `2025` and `2026`; `2025 365 <int>`; a `bushninjadots_2025.json` file appears; no directory whose name contains `${XDG_CACHE_HOME`.

---

## Task 2: Year-aware `GithubContrib` service

**Files:**
- Modify: `qml/shell/services/GithubContrib.qml`

**Interfaces:**
- Consumes: Task 1 CLI.
- Produces (public API):
  - `data` (var), `total` (int), `user` (string), `year` (int, selected), `years` (var, int[]), `loading` (bool), `error` (string), `hasData` (bool).
  - `setUser(name: string)`, `setYear(y: int)`, `refresh()`, `forceRefresh()` (all `void`).

- [ ] **Step 1: Add `year` and `years` to the frame and `update()`**

Add `years: []` to the `frame` object. Add a public `readonly property var years: root.frame.years || []` and keep `readonly property int year: root.frame.year` (frame already carries `year`). Extend `update(patch)` with the same `patch.years !== undefined ? patch.years : root.frame.years` pattern.

- [ ] **Step 2: Add `setYear(y)`**

```qml
function setYear(y) {
    var v = parseInt(y); if (!(v > 0)) return
    if (v === root.frame.year) return
    root.update({ year: v, status: "loading", error: "" })
    if (!root.frame.years || root.frame.years.length === 0)
        root.refreshYears()
    root.refresh()
}
```

- [ ] **Step 3: Make the main fetch year-aware**

Change the `fetch` Process `command` binding to:
`["python3", "-I", root.fetcher, "--year", String(root.frame.year || new Date().getFullYear())].concat(root._force ? ["--force"] : [])`.
In `Component.onCompleted`, seed the year first: `if (!root.frame.year) root.update({ year: new Date().getFullYear() })`.

- [ ] **Step 4: Add a `refreshYears()` + `fetchYears` Process**

New Process `fetchYears` with `command: ["python3", "-I", root.fetcher, root.frame.user, "--years"].concat(root._force ? ["--force"] : [])` (skip when `user` is empty). `StdioCollector.onStreamFinished`: parse; `root.update({ years: parsed.years || [] })`; if the selected `year` is not `> 0` or not in the list, set it to the max of `years` (fallback `new Date().getFullYear()`).

- [ ] **Step 5: Call `refreshYears()` on user change**

In `saveUserProcess.onExited` and in `readUserProcess`'s handler, after `root.update({...})`, call `root.refreshYears()` before `root.refresh()`. Guard against duplicate runs inside `refreshYears()` (`if (fetchYears.running) return`).

- [ ] **Step 6: Verify**

```bash
cd /home/bender/.config/desktop-widgets
bin/desktop-widgets restart; sleep 2; bin/desktop-widgets status
qs -p "$PWD" log 2>&1 | grep -aiE "GithubContrib|Unable to assign|is not defined|referenceerror" || echo "clean"
```
Expected: status `on`; `clean` (no GithubContrib errors). Continue past the harmless `PluginWidgetMenu.qml:54` warning and socket warnings.

---

## Task 3: `heatmapYear` setting + Hub persistence plumbing

**Files:**
- Modify: `qml/shell/modules/desktop/Singletons/Config.qml` (alias block ~135-147; adapter defaults ~316-327)
- Modify: `qml/hub/pages/WidgetsPage.qml` (`keys` ~40, `factory` ~67, JsonAdapter ~404-412)
- Modify: `qml/hub/schema/WidgetsPage.js` (heatmap rows ~666-714)

**Interfaces:**
- Produces: `Config.heatmapYear` (int, default `new Date().getFullYear()`) persisted in `settings/widgets.json`; a Hub schema row so it survives a Save.

- [ ] **Step 1: Config.qml alias + default**

Add `property alias heatmapYear: adapter.heatmapYear` under the heatmap aliases, and to the adapter object `property int heatmapYear: new Date().getFullYear()`.

- [ ] **Step 2: Hub whitelist + factory + adapter**

In `WidgetsPage.qml`: append `"heatmapYear"` to `keys`; add `"heatmapYear": new Date().getFullYear()` to `factory`; add `property int heatmapYear: new Date().getFullYear()` to the `cfgA` JsonAdapter.

- [ ] **Step 3: Schema row**

In `WidgetsPage.js`, after the `heatmapDesign` row add:
```js
{ "tab": "heatmap", "group": "GITHUB", "key": "heatmapYear", "label": "Year",
  "desc": "Calendar year to graph; the toolbar year selector also sets this",
  "ctl": "step", "src": "widgets.json", "lo": 2008, "hi": 2026 }
```

- [ ] **Step 4: Verify**

```bash
cd /home/bender/.config/desktop-widgets
grep -n "heatmapYear" qml/shell/modules/desktop/Singletons/Config.qml qml/hub/pages/WidgetsPage.qml qml/hub/schema/WidgetsPage.js
bin/desktop-widgets restart; sleep 2
qs -p "$PWD" log 2>&1 | grep -aiE "\.qml\[[0-9]|TypeError|ReferenceError|Unable to assign" || echo "clean"
```
Expected: `heatmapYear` present in all three files; loader log `clean`.

---

## Task 4: `HeatmapGraph.qml` (full-year graph)

**Files:**
- Create: `qml/shell/modules/desktop/heatmap/HeatmapGraph.qml`

**Interfaces:**
- Consumes: nothing from other tasks (pure presentation).
- Produces (used by Task 6):
  - In: `contributions` (var), `year` (int), `baseCol` (color), `stops` (var), `ink` (color), `dim` (color), `cellSize` (int, default 11), `cellGap` (int, default 2).
  - Out: `cells` (var), `gridWidth` (int), `gridHeight` (int), `stats` (var `{longestStreak:int, busiestDay:{date:string, count:int}, total:int}`), `pinnedDate` (string, the currently pinned ISO date; empty = none).
  - Signals: `dayClicked(var cell)`.

- [ ] **Step 1: Compute Monday-aligned cells**

`gridCols = 53`, `gridRows = 7`. For Jan 1 of `year`, `offset = (new Date(year,0,1).getDay() + 6) % 7` (Mon=0). Iterate `i` in `0..370`: `date = new Date(year,0,1+i-offset)`; `iso`; `inYear = date.getFullYear() === year`; `n = byDate[iso] || 0`; `future = date.getTime() > today`; push `{t, date: iso, n, future, level, inYear}` where `level = n === 0 ? 0 : Math.min(4, Math.ceil((n/peak)*4))` and `peak = max(1, max count in year)`. `x = weekIdx*(cellSize+gap)`, `y = dayIdx*(cellSize+gap)` with `weekIdx = Math.floor(i/7)`, `dayIdx = i%7`.

- [ ] **Step 2: Stats**

From the in-year cells: `total` = sum of `n`; `busiestDay` = the cell with max `n` (ignore `n === 0`; when all zero, `{date:"", count:0}`); `longestStreak` = longest run of consecutive in-year days with `n > 0` (skip the padded out-of-year days). Guard empty data.

- [ ] **Step 3: Render cells + labels**

`Item` width `gridWidth`, height `gridHeight`, `Repeater { model: root.cells; delegate: Rectangle { required property int index; required property var modelData; property var c: modelData; ... radius; color: (!c.inYear || c.future) ? "transparent" : (root.stops[c.level] || root.stops[0]); opacity: 0; Behavior on opacity { NumberAnimation { duration: 220 } }; Component.onCompleted: opacity = 1 } }`. Month labels: a `Repeater` over `0..11`, each `Text` (`["Jan".."Dec"]`) positioned above the first week-column whose first in-year day falls in that month; render only when the month has ≥1 in-year day. Weekday labels: left `Column` with `["Mon","Wed","Fri"]` at rows 0,2,4.

- [ ] **Step 4: Hover tooltip + click**

Each cell gets a `MouseArea` (`hoverEnabled: true`, `cursorShape: Qt.PointingHandCursor`): on `entered` set `root.hovered = c`; `onPositionChanged` same; on `exited` clear; `onClicked: root.dayClicked(c)`. A tooltip `Rectangle` (`visible: root.hovered`, `opacity: root.hovered ? 1 : 0`, `Behavior on opacity`) shows `<weekday>, <Mon D, YYYY> · <n> contributions`, positioned near the hovered cell. Cells with `pinnedDate === c.date` get a highlight ring (`border.width: 1`, `border.color: root.baseCol`).

- [ ] **Step 5: Verify (scratch harness)**

Create a throwaway `qml/shell/modules/desktop/heatmap/_scratch.qml` that instantiates `HeatmapGraph` with a small fake `contributions` array and the theme colors, run it headless, then delete it:
```bash
cd /home/bender/.config/desktop-widgets
QML_IMPORT_PATH="$PWD/qml" qs -p "$PWD" 2>&1 | grep -aiE "HeatmapGraph|ReferenceError|TypeError|Unable to assign" || echo "clean"
rm -f qml/shell/modules/desktop/heatmap/_scratch.qml
```
Expected: `clean`. (The authoritative check is the real Quickshell loader; `qmllint` exits non-zero without output on this project and is not authoritative.)

---

## Task 5: `HeatmapToolbar.qml` (hover-revealed controls)

**Files:**
- Create: `qml/shell/modules/desktop/heatmap/HeatmapToolbar.qml`

**Interfaces:**
- Consumes: presentation values from Task 6.
- Produces:
  - In: `displayName` (string), `year` (int), `years` (var), `total` (int), `loading` (bool), `stats` (var), `pinned` (var), `ink` (color), `dim` (color).
  - Signals: `userEdited(string cleanUser)`, `yearStep(int delta)`, `syncRequested()`.

- [ ] **Step 1: Layout**

A `Row` (height 22) with: the username `Text` (click → edit) and a hidden `TextInput` (same edit pattern as the current header: `Keys.onEnterPressed` emits `userEdited(text)`; `Escape` cancels); a spacer; `Text "‹"` / `Text year` / `Text "›"` emitting `yearStep(-1)` / `yearStep(1)` (disable/omit stepping when at list bounds); a refresh `Text "↻"` emitting `syncRequested()` (shows a subtle rotate/`Behavior` while `loading`).

- [ ] **Step 2: Stats / pin line**

A second `Text` (size 10, `dim`): when `pinned` has a date show `"<date> · <count> contributions"`; else show `"<longestStreak>d streak · busiest <busiestDay.date> (<n>)"` when `stats.total > 0`; else the existing `set your GitHub username` / `loading…` / `unavailable` / `"<total> this year"` messaging.

- [ ] **Step 3: Verify**

Loader-log check as in Task 4 (no `HeatmapToolbar` `TypeError`/`ReferenceError`).

---

## Task 6: `HeatmapWidget.qml` orchestrator

**Files:**
- Modify: `qml/shell/modules/desktop/heatmap/HeatmapWidget.qml`

**Interfaces:**
- Consumes: Task 2 (`GithubContrib.{data,total,user,year,years,loading,error,setYear,setUser,forceRefresh}`), Task 3 (`Config.heatmapYear`), Tasks 4 & 5.
- Produces: the same widget contract as today (`underL`, `inkColorA`, `s`, `active`), so `Desktop.qml` needs no change.

- [ ] **Step 1: Keep vertical mode inline; route horizontal to HeatmapGraph**

Keep `cleanUser`, `syncName`, `applyUser`, both `Connections`, the vertical `cells`/grid, and the toggle. When `vertical === false`, instantiate `HeatmapGraph` bound to `GithubContrib.data`, `GithubContrib.year`, the ramp (`stops`/`baseCol`), and the theme colors; forward its `dayClicked` to set the pinned cell. `WidgetMenu.qml` needs **no change** — its Design row already cycles `auto/horizontal/vertical` and Sync now already calls `forceRefresh()` (which now targets the selected year).

- [ ] **Step 2: Wire the toolbar**

Instantiate `HeatmapToolbar` with `displayName`, `year: GithubContrib.year`, `years: GithubContrib.years`, `total`, `loading`, `stats`, `pinned`, `ink`, `dim`. Connect: `onUserEdited(u) → applyUser(u)`; `onYearStep(d) → pick the neighbour year in GithubContrib.years and Config.set("heatmapYear", y) + GithubContrib.setYear(y)`; `onSyncRequested → GithubContrib.forceRefresh()`.

- [ ] **Step 3: Hover-reveal**

Wrap the toolbar in an `Item` whose `opacity` follows a widget-level `hoverEnabled` `MouseArea` (`HoverHandler` or `MouseArea { hoverEnabled: true }`) via `Behavior on opacity { NumberAnimation { duration: 150 } }`; overlay the toolbar at the top edge so nothing shifts. Follow `Config.heatmapYear` live in the existing `Connections` (`onHeatmapYearChanged: GithubContrib.setYear(Config.heatmapYear)`) and seed it in `Component.onCompleted`.

- [ ] **Step 4: Size / chrome**

`box.width` = `vertical ? 160 : gridWidth + padding`; `box.height` derives from content (header + graph/labels + toolbar), not a constant. `implicitWidth/Height` = `box.* * root.s`.

- [ ] **Step 5: Verify**

```bash
cd /home/bender/.config/desktop-widgets
bin/desktop-widgets restart; sleep 2; bin/desktop-widgets status
hyprctl layers 2>&1 | grep -ioE "namespace: desktop-widgets, pid: [0-9]+"
qs -p "$PWD" log 2>&1 | grep -aiE "\.qml\[[0-9]|TypeError|ReferenceError|Unable to assign|is not defined" || echo "clean"
```
Expected: status `on`; a `desktop-widgets` layer with a pid; `clean`.

---

## Task 7: Hub preview mirrors the full-year graph

**Files:**
- Modify: `qml/hub/HeatmapPreview.qml`
- Modify: `qml/hub/pages/WidgetsPage.qml` (loader binding ~496-497)

**Interfaces:**
- Consumes: Task 3 (`heatmapYear`), sample data.

- [ ] **Step 1: Full-year sample render**

Replace the 12-week sample with a full-year (Monday-aligned, 53×7) sample grid. Keep `design` handling: `horizontal`/`auto` → full-year; `vertical` → keep the existing compact 12-week preview. Add a `year` property (int) and render month labels above (same rule as Task 4, simplified). Keep `required property int index` / `required property var modelData` on both delegates.

- [ ] **Step 2: Bind year in the loader**

In `WidgetsPage.qml` `heatmapPrevC.onLoaded`, add `item.year = Qt.binding(() => pg.draft.heatmapYear || new Date().getFullYear())`.

- [ ] **Step 3: Verify**

```bash
cd /home/bender/.config/desktop-widgets
qs -p "$PWD" ipc call widgets editor   # open
qs -p "$PWD" log 2>&1 | grep -aiE "HeatmapPreview|\.qml\[[0-9]|ReferenceError|TypeError" || echo "clean"
qs -p "$PWD" ipc call widgets editor   # close
```
Expected: `clean` (only the harmless `qt.qpa.wayland.textinput` notice is acceptable).

---

## Final Verification (after all tasks)

- [ ] `python3 -m py_compile bin/github-contributions` passes.
- [ ] `bin/desktop-widgets restart` → status `on`; `hyprctl layers` shows the `desktop-widgets` surface.
- [ ] `qs -p <dir>` load and `qs -p <dir> log` show **no** `.qml[...]` / `TypeError` / `ReferenceError` / `Unable to assign` / `is not defined` (only the pre-existing `PluginWidgetMenu.qml:54 Duplicate signal name` warning and unrelated socket warnings).
- [ ] No leftover probe `console.log`s in any modified QML.
- [ ] User visually confirms: horizontal shows weeks across × days down with month/weekday labels; hover reveals the toolbar and a per-day tooltip; `‹ year ›` changes the year; Sync now refetches; vertical still shows the compact 12-week grid.
- [ ] Nothing committed or pushed (AGENTS.md).
