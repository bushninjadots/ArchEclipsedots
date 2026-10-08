#!/bin/bash
# Recolour the desktop from the current wallpaper with matugen, in the
# system's light/dark mode. qs-wallpaperpicker does the same when a wallpaper
# is set; this runs it again when the mode changes (system-theme.sh switch).

set -euo pipefail

readonly SCRIPTS_DIR="${HOME}/.config/hypr/theme/scripts"
# A still of the wallpaper (a video's frame), kept by qs-wallpaperpicker.
readonly STILL="${HOME}/.cache/current_wallpaper"

command -v matugen >/dev/null || { echo "matugen is not installed" >&2; exit 1; }
[[ -e "${STILL}" ]] || { echo "No wallpaper set yet (${STILL} missing)" >&2; exit 0; }

mode="$("${SCRIPTS_DIR}/system-theme.sh" get)"
matugen image "$(readlink -f "${STILL}")" --source-color-index 0 -m "${mode}"
