# desktop-widgets

Desktop widgets for ArchEclipse, taken from the [Ryoku](https://github.com/Ryoku-dev/ryoku)
shell: clock (13 faces), calendar, music (with visualizer), notes, system stats,
weather and an all-in-one card. They sit on the wallpaper, under your windows:
drag a widget to move it, right-click it (or the bare desktop) for its options.

- **Editor:** left sidebar → Settings → **Desktop Widgets** → *Open widget
  editor* (or `desktop-widgets editor`). Turn widgets on, pick their style, size,
  opacity and placement; *Save* puts them on the desktop.
- **On/off:** the *Show desktop widgets* switch in the same section
  (`desktop-widgets enable|disable`).
- Settings live in `~/.config/desktop-widgets/settings/widgets.json`; notes in
  `~/.local/state/desktop-widgets/desktop-notes.txt`.

It runs as its own Quickshell instance (`bin/desktop-widgets`, started by
Hyprland's `config/exec.lua`), next to the ArchEclipse shell and
qs-wallpaperpicker.

## What differs from Ryoku

Ryoku's widgets talk to its `ryoku-shell` daemon. ArchEclipse has no daemon, so:

- **Colours:** matugen writes the palette the widgets read
  (`~/.cache/desktop-widgets/colors.json`, template `~/.config/matugen/templates/desktop-widgets-colors.json`),
  and its post hook runs `bin/wallpaper-tone`, which writes the wallpaper
  lightness map (`~/.cache/desktop-widgets/wallpaper-tone.json`) the widgets use to pick
  light or dark text.
- **Weather:** `bin/weather` is a Python port of the daemon's weather
  fetch (Open-Meteo, no key; place from Ryoku's weather setting, else your IP),
  run every 15 minutes by `qml/shell/services/Weather.qml`.
- **Music:** cover art falls back to the player's own (MPRIS); synced lyrics
  and Spotify Canvas need the daemon and are not available.
- **Wallpaper:** the host never paints one (`paintWallpaper: false` in
  `qml/shell/modules/desktop/Desktop.qml`); qs-wallpaperpicker does.
- The editor is the Ryoku Hub's *Desktop Widgets* page in its own window
  (`WidgetEditor.qml`).
- **Looks follow ArchEclipse:** JetBrainsMono everywhere (Ryoku's Fraunces /
  Space Grotesk aren't used), 10px radius, and motion from ArchEclipse's
  Settings → Animations (`Ryoku/Ui/Singletons/Tokens.qml` reads
  `~/.cache/quickshell/settings/settings.json`). Ryoku's fixed vermillion
  "brand" accent and the editor previews' sample colours follow the matugen
  palette instead. Light/dark, 24h time, date language and units follow the
  system (matugen mode, `LC_TIME`, `LC_MEASUREMENT`).
- **Right-click menu:** styled like ArchEclipse panels (translucent at the
  shell's opacity with Hyprland blur, 15% border, 10px radius, the shell font,
  accent-tinted hover, no kanji glosses). *Widget editor…* opens
  `WidgetEditor.qml`, *Reload widgets* restarts this instance, *Change
  wallpaper* opens qs-wallpaperpicker. Depth/Parallax and Spotify Canvas need
  ryoku-shell, so they are hidden.
- **Visualizer:** Ryoku's desktop audio visualizer runs per screen
  (`~/.config/desktop-widgets/settings/visualizer.json`; right-click the desktop to place or
  restyle it). It uses cava on the PipeWire output and only analyses while
  audio is playing.
- **Aura look = iNiR Organic Edge:** the `aura` style draws with iNiR's own
  Organic Edge files (`qml/shell/modules/visualizer/organic/`, see its NOTICE);
  `OrganicAura.qml` maps the instance's `organic` settings onto it. Scenes,
  materials, shape, light, colours, response and silence are in the edit bar.
  With ArchEclipse's Shell frame on, it starts at the frame's inner line.

`qml/` is vendored from Ryoku (module names renamed to `Eclipse.*`; Ryoku's bar, launcher, dock and other shell modules removed) (`ryoku/shell/quickshell/shell`, `ryoku/ui`,
`ryoku/shell/framebars`, `ryoku/shell/quickshell/plugins/kit`,
`ryoku/hub/quickshell`) with the small patches above.

## License

GPL-3.0, like Ryoku and ArchEclipse. See `LICENSE` and Ryoku's `NOTICE`.
