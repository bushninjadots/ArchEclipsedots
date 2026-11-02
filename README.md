# dotfiles

My Arch (EndeavourOS) + Hyprland 0.57 desktop configuration. The shell on top of it — bar, panels,
notch, Control Nexus, screen frame, BMO — is **mooi**, built on [pleamar](https://github.com/k4ditano/pleamar).
It lives in its own (private) repository, together with an installer that restores this whole setup.

This started as a fork of [AymanLyesri/ArchEclipse](https://github.com/AymanLyesri/ArchEclipse). ArchEclipse's
shell, installer, documentation and screenshots have since been removed; what remains is my own
configuration.

## What is here

| Path | What it is |
| --- | --- |
| `.config/hypr/` | Hyprland, in Lua: `hyprland.lua` loads `config/*.lua`, then `config/custom/*.lua`. `config/custom/mooi.lua` starts mooi at login and binds its keys; `scripts/` and `theme/scripts/` are the helpers the config calls (screenshots, volume, brightness, idle, lock, displays, theming). |
| `.config/qs-wallpaperpicker/` | Skwd Wall, the wallpaper picker (Quickshell). It sets the wallpaper and runs matugen. |
| `.config/wallpaper-styles/` | The picker's layouts (Slices, Hex, Hand, …) and its dispatcher. |
| `.config/desktop-widgets/` | Desktop widgets (Quickshell, vendored from Ryoku): clock, weather, lyrics, notes. |
| `.config/matugen/` | Colours from the wallpaper, written into kitty, GTK, Qt and the shell. |
| `.config/kitty/`, `.zshrc`, `.config/starship.toml` | Terminal and shell. |
| `.config/btop/`, `.config/cava/`, `.config/fastfetch/`, `.config/pipewire/` | Smaller tools. |
| `.icons/` | The phinger cursors. |

The repository's root is the home folder: `.gitignore` ignores everything there and lets only these
paths back in.

## Keys

mooi's keys are chosen in its Settings (→ Keys) and bound by `config/custom/mooi.lua`. By default,
`SUPER + ALT` and:

| Key | Opens |
| --- | --- |
| `Space` | search |
| `S` · `C` | settings · system |
| `O` · `W` | overview · this window |
| `P` · `M` | wallpaper · music player |
| `D` · `E` · `T` | screenshot · edit the bar · light/dark |
| `SHIFT + Space` | stop mooi |

`SUPER + SHIFT + B` (re)starts the shell. Hyprland's own bindings are in
[`config/bind.lua`](.config/hypr/config/bind.lua).

## On another machine

The whole desktop (packages, pleamar, this configuration, mooi and its settings) is restored by mooi's
`setup/install.sh`, which keeps its own captured copy of these files. To take only this configuration,
copy what you want from a clone:

```sh
git clone https://github.com/bushninjadots/ArchEclipsedots.git ~/dotfiles-src
cp -r ~/dotfiles-src/.config/hypr ~/.config/      # and so on, for each folder above
```

The monitor is set for a 1920×1080 laptop panel (`eDP-1`) in `config/monitor.lua`.

## Licence

GPL-3.0, as the ArchEclipse code this began from (see `LICENSE`).
