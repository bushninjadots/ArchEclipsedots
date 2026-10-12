#!/bin/bash
# Wires apps to the palette files matugen just wrote (config.toml, "apps")
# and nudges the ones that can reload live. Idempotent: each app is pointed
# at its file once, then this only reloads. Never fails matugen.
set -u
C="${XDG_CONFIG_HOME:-$HOME/.config}"

# btop: select the theme (btop reads it on start / theme change).
if [ -f "$C/btop/btop.conf" ]; then
    grep -q '^color_theme = "archeclipse"' "$C/btop/btop.conf" \
        || sed -i 's|^color_theme = .*|color_theme = "archeclipse"|' "$C/btop/btop.conf"
fi

# cava: use the theme file, then reload colours in running instances.
if [ -f "$C/cava/config" ]; then
    if ! grep -q "^theme = 'archeclipse'" "$C/cava/config"; then
        # Under [color]: replace the commented default or append after the header.
        if grep -q "^; theme = " "$C/cava/config"; then
            sed -i "s|^; theme = .*|theme = 'archeclipse'|" "$C/cava/config"
        else
            sed -i "/^\[color\]/a theme = 'archeclipse'" "$C/cava/config"
        fi
    fi
    pkill -USR2 -x cava 2>/dev/null
fi

# Vesktop: tick the theme (only while Vesktop is closed — it rewrites its
# settings on exit). It picks up file changes live once ticked.
VS="$C/vesktop/settings/settings.json"
if [ -f "$VS" ] && ! pgrep -x vesktop >/dev/null && command -v jq >/dev/null; then
    if ! jq -e '.enabledThemes | index("archeclipse.theme.css")' "$VS" >/dev/null 2>&1; then
        tmp=$(mktemp) && jq '.enabledThemes = ((.enabledThemes // []) - ["midnight-ryoku.theme.css"] + ["archeclipse.theme.css"])' "$VS" > "$tmp" && mv "$tmp" "$VS"
    fi
fi

# Zen: copy into the profile the browser opens and import it last in
# userChrome.css (after any other theme, so it wins).
ZEN="$C/zen"
if [ -f "$ZEN/installs.ini" ] && [ -f "$HOME/.cache/archeclipse/zen-colors.css" ]; then
    prof=$(awk -F= '/^Default=/{print $2; exit}' "$ZEN/installs.ini")
    P="$ZEN/$prof"
    if [ -n "$prof" ] && [ -d "$P" ]; then
        mkdir -p "$P/chrome"
        cp "$HOME/.cache/archeclipse/zen-colors.css" "$P/chrome/archeclipse-colors.css"
        touch "$P/chrome/userChrome.css"
        grep -q 'archeclipse-colors.css' "$P/chrome/userChrome.css" \
            || { # @import must precede rules: after the last one, else first.
                 n=$(grep -n '^@import' "$P/chrome/userChrome.css" | tail -1 | cut -d: -f1)
                 if [ -n "$n" ]; then sed -i "${n}a @import \"archeclipse-colors.css\";" "$P/chrome/userChrome.css"
                 else sed -i '1i @import "archeclipse-colors.css";' "$P/chrome/userChrome.css"; fi; }
        grep -q 'legacyUserProfileCustomizations.stylesheets' "$P/user.js" 2>/dev/null \
            || echo 'user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);' >> "$P/user.js"
    fi
fi

# Spotify: when the ArchEclipse theme is selected, refresh the patched
# client's stylesheets (no restart; it shows on Spotify's next start).
SP="$C/spicetify/config-xpui.ini"
if command -v spicetify >/dev/null && [ -f "$SP" ]; then
    touch "$C/spicetify/Themes/ArchEclipse/user.css"
    if grep -q '^current_theme *= *ArchEclipse' "$SP"; then
        timeout 30 spicetify -n -q refresh >/dev/null 2>&1 &
    fi
fi
exit 0
