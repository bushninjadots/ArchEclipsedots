#!/usr/bin/env bash
set -euo pipefail

# Usage: screenshot.sh --now [output.png] | --area [output.png]
#   Second arg overrides the destination path (must end in .png).
#   Set SCREENSHOT_OPTIMIZE=1 to run the (slow) ImageMagick strip/recompress.
timestamp=$(date +%Y%m%d_%H%M%S)
screenshot_dir="$HOME/Pictures/Screenshots"
screenshot_fullscreen_dir="$screenshot_dir/fullscreen"
screenshot_area_dir="$screenshot_dir/area"

# create screenshot directory if it doesn't exist
mkdir -p "$screenshot_dir"
mkdir -p "$screenshot_fullscreen_dir"
mkdir -p "$screenshot_area_dir"

mode="${1:-}"
custom_out="${2:-}"

if [[ "$mode" == "--now" ]]; then
    img="${custom_out:-$screenshot_fullscreen_dir/screenshot_$timestamp.png}"
    # Full output (PNG: Qt/Quickshell has no webp plugin, so PNG is
    # required for the notification preview and a correct image/png paste)
    grimblast --freeze save screen "$img" || exit 1

elif [[ "$mode" == "--area" ]]; then
    img="${custom_out:-$screenshot_area_dir/screenshot_area_$timestamp.png}"
    # Select region (non-zero exit = user cancelled, stay silent)
    grimblast --freeze save area "$img" || exit 1

else
    echo "Available Options : --now --area" >&2
    exit 1
fi

# Optional PNG optimize (off by default: magick recompress dominates
# screenshot latency; grim output is already fine for most uses)
if [[ "${SCREENSHOT_OPTIMIZE:-0}" == "1" ]]; then
    if command -v magick >/dev/null 2>&1; then
        magick "$img" -strip -define png:compression-level=6 "$img"
    fi
fi

# Send image to clipboard (bytes must match the declared MIME type)
wl-copy --type image/png < "$img"

# Notify with the shot as a preview and what to do with it (after
# Serpantinum / Ryoku's ryoshot). notify-send waits for the chosen action, so
# it runs detached; the shot is already saved and on the clipboard.
(
    act=$(timeout 300 notify-send -a "Screenshot" -i "$img" -h "string:image-path:$img" \
        -A edit="Edit" -A folder="Show in folder" -A delete="Delete" \
        "Screenshot saved" "Copied to clipboard · $(basename "$img")" 2>/dev/null) || exit 0
    case "$act" in
        edit)
            if command -v satty >/dev/null; then
                satty --filename "$img" --output-filename "$img" --copy-command wl-copy --early-exit
            elif command -v swappy >/dev/null; then
                swappy -f "$img" -o "$img"
            fi ;;
        folder)
            # Highlight the file where a file manager supports it.
            dbus-send --session --dest=org.freedesktop.FileManager1 --type=method_call \
                /org/freedesktop/FileManager1 org.freedesktop.FileManager1.ShowItems \
                array:string:"file://$img" string:"" 2>/dev/null || xdg-open "$(dirname "$img")" ;;
        delete)
            rm -f -- "$img" && notify-send -a "Screenshot" -t 2500 "Screenshot deleted" "$(basename "$img")" ;;
    esac
) >/dev/null 2>&1 &
disown
