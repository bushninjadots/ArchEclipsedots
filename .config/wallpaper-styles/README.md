# wallpaper-styles

Alternative wallpaper picker layouts for ArchEclipse: **Slices, Wall, Hex,
Mosaic, Hand, Sandy and Grid**, next to qs-wallpaperpicker's card **Deck**.
Choose one in the left sidebar (Settings → Wallpaper Picker), in either
picker's own settings (the gear), or with `bin/wallpaper-picker set STYLE`.
SUPER+W runs `bin/wallpaper-picker toggle`, which opens the chosen one.

Every style applies wallpapers through qs-wallpaperpicker
(`qs-wallpaperpicker set FILE`), so the wallpaper is drawn, transitioned and
recoloured (matugen) the same way whichever picker you use. Both read the same
folder (qs-wallpaperpicker's `settings.json`, `~/Pictures/wallpapers`).

- `bin/wallpaper-index` builds `~/.cache/wallpaper-styles/index.json`:
  640x360 thumbnails and the colour bucket each wallpaper sorts and filters by.
  It runs in the background (idle priority) when the picker starts and on
  Refresh; only new or changed files are processed.
- `qml/services/DaemonClient.qml` answers the picker locally (list, apply,
  favourites, state). The original's daemon-only extras (Steam Workshop,
  Wallpaper Engine scenes, effects, playlists, rotation, theme and rice
  catalogues, scraped library sources) are removed or hidden; Wallhaven is the
  online source.
- Colours follow ArchEclipse's matugen palette (`~/.cache/quickshell/colors.json`).
- `config.json` holds the picker's own layout settings (Settings → Selector).

The picker UI is based on skwd-wall by liixini (MIT, see `LICENSE`), as
adapted in the Ryoku project's Ryogami wall-ui.
