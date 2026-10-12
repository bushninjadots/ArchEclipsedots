#!/usr/bin/env bash
# Saved looks (after impasto's profiles): the whole desk under a name.
#
#   looks.sh save NAME     snapshot the bar/frame/shell settings, the desktop
#                          widgets, the wallpaper and a small preview
#   looks.sh apply NAME    put it all back (the shell and widgets reload live)
#   looks.sh list          one JSON object per line: name, saved, thumb, wallpaper
#   looks.sh delete NAME
#
# Your account bits (profile picture, desktop name) are never swapped.
set -u
LOOKS="${XDG_DATA_HOME:-$HOME/.local/share}/archeclipse/looks"
SETTINGS="$HOME/.cache/quickshell/settings/settings.json"
WIDGETS="${XDG_CONFIG_HOME:-$HOME/.config}/desktop-widgets/settings/widgets.json"
PICKER="${XDG_CONFIG_HOME:-$HOME/.config}/qs-wallpaperpicker/bin/qs-wallpaperpicker"

name_ok() { [[ -n "${1:-}" && "$1" != */* && "$1" != .* ]]; }

case "${1:-}" in
save)
    name_ok "${2:-}" || { echo "looks: bad name" >&2; exit 1; }
    d="$LOOKS/$2"; mkdir -p "$d"
    [ -f "$SETTINGS" ] && cp "$SETTINGS" "$d/settings.json"
    [ -f "$WIDGETS" ] && cp "$WIDGETS" "$d/widgets.json"
    wp=$("$PICKER" current 2>/dev/null || readlink -f "$HOME/.cache/current_wallpaper_source")
    printf '%s\n' "$wp" > "$d/wallpaper.txt"
    # Preview: a small shot of the screen as it looks now.
    grim -s 0.18 -t png "$d/thumb.png" 2>/dev/null || true
    date +%s > "$d/saved"
    echo "saved $2"
    ;;
apply)
    name_ok "${2:-}" || exit 1
    d="$LOOKS/$2"; [ -d "$d" ] || { echo "looks: no look '$2'" >&2; exit 1; }
    if [ -f "$d/settings.json" ] && [ -f "$SETTINGS" ]; then
        # Keep the current account section; Settings.qml watches the file.
        tmp=$(mktemp)
        jq --slurpfile cur "$SETTINGS" '.profile = ($cur[0].profile // .profile)' "$d/settings.json" > "$tmp" \
            && mv "$tmp" "$SETTINGS"
    fi
    if [ -f "$d/widgets.json" ]; then
        cp "$d/widgets.json" "$WIDGETS"
        "${XDG_CONFIG_HOME:-$HOME/.config}/desktop-widgets/bin/desktop-widgets" restart >/dev/null 2>&1 &
    fi
    wp=$(cat "$d/wallpaper.txt" 2>/dev/null)
    [ -n "$wp" ] && [ -f "$wp" ] && "$PICKER" set "$wp" >/dev/null 2>&1
    notify-send -a "Looks" "Look applied" "$2" 2>/dev/null
    echo "applied $2"
    ;;
list)
    [ -d "$LOOKS" ] || exit 0
    for d in "$LOOKS"/*/; do
        [ -d "$d" ] || continue
        n=$(basename "$d")
        jq -cn --arg name "$n" --arg saved "$(cat "$d/saved" 2>/dev/null || echo 0)" \
            --arg thumb "$([ -f "$d/thumb.png" ] && echo "$d/thumb.png")" \
            --arg wallpaper "$(cat "$d/wallpaper.txt" 2>/dev/null)" \
            '{name: $name, saved: ($saved | tonumber), thumb: $thumb, wallpaper: $wallpaper}'
    done
    ;;
delete)
    name_ok "${2:-}" || exit 1
    rm -rf -- "${LOOKS:?}/$2" && echo "deleted $2"
    ;;
*)
    sed -n '2,12p' "$0"; exit 1 ;;
esac
