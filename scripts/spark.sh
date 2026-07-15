#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════
# Spark for Linux — wofi-based quick launcher
# Usage: spark.sh <category_id>   (e.g. spark.sh code)
#        spark.sh --search        (global search all categories)
#        spark.sh --scan          (scan & import .desktop apps)
#        spark.sh --recent        (show recent launches)
# ═══════════════════════════════════════════════════════
set -euo pipefail

# ── paths ──────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="${SPARK_CONFIG:-$PROJECT_DIR/config/config.json}"
RECENT_FILE="${XDG_DATA_HOME:-$HOME/.local/share}/spark/recent.json"
HISTORY_DIR="$(dirname "$RECENT_FILE")"

# ── deps check ─────────────────────────────────────────
for cmd in jq wofi; do
    if ! command -v "$cmd" &>/dev/null; then
        notify-send -u critical "Spark" "$cmd is required. Install: sudo pacman -S $cmd"
        exit 1
    fi
done

mkdir -p "$HISTORY_DIR"
[[ -f "$RECENT_FILE" ]] || echo '[]' > "$RECENT_FILE"

# ── wofi icon format: icon\x1ftext ─────────────────────
# wofi with allow_images=true uses:  icon_name<US>display_text
# where <US> = Unit Separator (ASCII 31)
US=$'\x1f'
TAB=$'\t'

# ── icon lookup for app command ────────────────────────
# Try to find a .desktop file whose Exec matches the command
_icon_for_app() {
    local cmd="$1"
    local icon="application-x-executable"

    # Search .desktop files for matching Exec
    for dir in /usr/share/applications ~/.local/share/applications; do
        [[ -d "$dir" ]] || continue
        for f in "$dir"/*.desktop; do
            [[ -f "$f" ]] || continue
            local exec_line
            exec_line="$(grep -m1 '^Exec=' "$f" 2>/dev/null | cut -d= -f2- | sed 's/ *%[fFuUdDnNickvm]//g')"
            # Match: exec_line contains the command, or command matches the binary name
            if [[ "$exec_line" == "$cmd"* ]] || [[ "$exec_line" == *"/$cmd "* ]] || [[ "$exec_line" == *"/$cmd" ]]; then
                local found_icon
                found_icon="$(grep -m1 '^Icon=' "$f" 2>/dev/null | cut -d= -f2-)"
                [[ -n "$found_icon" ]] && icon="$found_icon" && break
            fi
        done
        [[ "$icon" != "application-x-executable" ]] && break
    done

    # Also check if command itself is a known binary
    if [[ "$icon" == "application-x-executable" ]]; then
        for dir in /usr/share/applications ~/.local/share/applications; do
            [[ -d "$dir" ]] || continue
            for f in "$dir"/*.desktop; do
                [[ -f "$f" ]] || continue
                local desktop_name
                desktop_name="$(basename "$f" .desktop)"
                if [[ "$desktop_name" == "$cmd" ]] || [[ "$desktop_name" == *"$cmd"* ]]; then
                    local found_icon
                    found_icon="$(grep -m1 '^Icon=' "$f" 2>/dev/null | cut -d= -f2-)"
                    [[ -n "$found_icon" ]] && icon="$found_icon" && break 2
                fi
            done
        done
    fi

    echo "$icon"
}

# ── icon for type ──────────────────────────────────────
icon_for_type() {
    local type="$1" cmd="$2"
    case "$type" in
        app)    _icon_for_app "$cmd" ;;
        url)    echo "web-browser" ;;
        folder) echo "folder" ;;
        script) echo "utilities-terminal" ;;
        *)      echo "application-x-executable" ;;
    esac
}

# ── helpers ────────────────────────────────────────────
log_recent() {
    local now
    now="$(date -Iseconds)"
    local tmp
    tmp="$(mktemp)"
    jq --arg n "$1" --arg t "$2" --arg c "$3" --arg d "$now" '
        [.[] | select(.command != $c)] |
        [{"name":$n,"type":$t,"command":$c,"time":$d}] + . |
        .[0:20]
    ' "$RECENT_FILE" > "$tmp" && mv "$tmp" "$RECENT_FILE"
}

launch_item() {
    local type="$1" cmd="$2" name="$3"
    log_recent "$name" "$type" "$cmd"
    case "$type" in
        app)
            if gtk-launch "$cmd" 2>/dev/null; then return; fi
            setsid "$cmd" &>/dev/null &
            ;;
        url)    xdg-open "$cmd" &>/dev/null & ;;
        folder) xdg-open "$cmd" &>/dev/null & ;;
        script) setsid bash -c "$cmd" &>/dev/null & ;;
        *)      setsid "$cmd" &>/dev/null & ;;
    esac
}

# ── show wofi menu from a temp file ────────────────────
# Input file lines: icon<US>display<TAB>type<TAB>command
show_menu() {
    local prompt="$1"
    local entries_file="$2"

    local chosen
    chosen="$(wofi \
        --dmenu \
        --prompt "$prompt" \
        --width 450 --height 400 \
        --matching fuzzy \
        --sort-by=alphabetical \
        --allow-markup \
        --allow-images \
        --conf "$PROJECT_DIR/themes/wofi.conf" \
        --style "$PROJECT_DIR/themes/wofi.css" \
        < "$entries_file" 2>/dev/null)" || exit 0

    [[ -z "$chosen" ]] && exit 0

    # Parse: icon<US>display<TAB>type<TAB>command
    local display type cmd
    display="$(echo "$chosen" | cut -d"$TAB" -f1 | sed "s/.*${US}//")"
    type="$(echo "$chosen" | cut -d"$TAB" -f2)"
    cmd="$(echo "$chosen" | cut -d"$TAB" -f3)"

    [[ -z "$type" || -z "$cmd" ]] && exit 1
    launch_item "$type" "$cmd" "$display"
}

# ── build category entries to tmpfile ──────────────────
build_category_entries() {
    local cat_id="$1"
    local tmpfile="$2"

    while IFS="$TAB" read -r name type cmd; do
        local icon
        icon="$(icon_for_type "$type" "$cmd")"
        echo "${icon}${US}${name}${TAB}${type}${TAB}${cmd}"
    done < <(jq -r --arg id "$cat_id" '
        .categories[] | select(.id == $id) | .items[] |
        "\(.name)\t\(.type)\t\(.command)"
    ' "$CONFIG_FILE") > "$tmpfile"
}

# ── build all entries for global search ────────────────
build_all_entries() {
    local tmpfile="$1"

    while IFS="$TAB" read -r name type cmd; do
        local icon
        icon="$(icon_for_type "$type" "$cmd")"
        echo "${icon}${US}${name}${TAB}${type}${TAB}${cmd}"
    done < <(jq -r '
        .categories[] | .items[] |
        "\(.name)\t\(.type)\t\(.command)"
    ' "$CONFIG_FILE") > "$tmpfile"
}

# ── build recent entries ───────────────────────────────
build_recent_entries() {
    local tmpfile="$1"

    while IFS="$TAB" read -r name type cmd; do
        local icon
        icon="$(icon_for_type "$type" "$cmd")"
        echo "${icon}${US}${name}${TAB}${type}${TAB}${cmd}"
    done < <(jq -r '
        .[] | "\(.name)\t\(.type)\t\(.command)"
    ' "$RECENT_FILE") > "$tmpfile"
}

# ── show category list ─────────────────────────────────
show_category_list() {
    local tmpfile
    tmpfile="$(mktemp)"
    trap "rm -f '$tmpfile'" EXIT

    # Category icons — use GTK icon names
    local -A cat_icons=(
        [code]="accessories-text-editor"
        [browser]="web-browser"
        [ai]="preferences-system"
        [document]="x-office-document"
        [tools]="utilities-terminal"
        [social]="internet-chat"
        [folders]="folder"
        [pin]="view-pin"
    )

    jq -r '
        .categories[] |
        "\(.id)\t\(.name)\t\(.items | length)\t\(.hotkey)"
    ' "$CONFIG_FILE" | while IFS="$TAB" read -r id name count hotkey; do
        local icon="${cat_icons[$id]:-application-x-executable}"
        echo "${icon}${US}${name} (${count}) — ${hotkey}${TAB}cat${TAB}${id}"
    done > "$tmpfile"

    local chosen
    chosen="$(wofi \
        --dmenu \
        --prompt "Spark" \
        --width 400 --height 350 \
        --matching fuzzy \
        --allow-images \
        --conf "$PROJECT_DIR/themes/wofi.conf" \
        --style "$PROJECT_DIR/themes/wofi.css" \
        < "$tmpfile" 2>/dev/null)" || exit 0

    [[ -z "$chosen" ]] && exit 0

    local cat_id
    cat_id="$(echo "$chosen" | cut -d"$TAB" -f3)"

    local items_file
    items_file="$(mktemp)"
    trap "rm -f '$tmpfile' '$items_file'" EXIT
    build_category_entries "$cat_id" "$items_file"

    [[ -s "$items_file" ]] || { notify-send "Spark" "No items in $cat_id"; exit 0; }
    show_menu "$cat_id" "$items_file"
}

# ── main ───────────────────────────────────────────────
case "${1:---list}" in
    --list|-l)
        show_category_list
        ;;
    --search|-s)
        tmpfile="$(mktemp)"
        trap "rm -f '$tmpfile'" EXIT
        build_all_entries "$tmpfile"
        [[ -s "$tmpfile" ]] || { notify-send "Spark" "No items configured"; exit 0; }
        show_menu "Search All" "$tmpfile"
        ;;
    --recent|-r)
        tmpfile="$(mktemp)"
        trap "rm -f '$tmpfile'" EXIT
        build_recent_entries "$tmpfile"
        [[ -s "$tmpfile" ]] || { notify-send "Spark" "No recent launches"; exit 0; }
        show_menu "Recent" "$tmpfile"
        ;;
    --scan)
        exec "$SCRIPT_DIR/scan-apps.sh"
        ;;
    --help|-h)
        cat <<'EOF'
Spark for Linux — wofi-based quick launcher

Usage:
  spark.sh                  Show category list
  spark.sh <category_id>    Open category directly (e.g. spark.sh code)
  spark.sh --search         Search across all categories
  spark.sh --recent         Show recent launches
  spark.sh --scan           Scan & import .desktop apps
  spark.sh --help           Show this help
EOF
        ;;
    *)
        cat_id="$1"
        if ! jq -e --arg id "$cat_id" '.categories[] | select(.id == $id)' "$CONFIG_FILE" &>/dev/null; then
            notify-send -u critical "Spark" "Category '$cat_id' not found"
            exit 1
        fi
        tmpfile="$(mktemp)"
        trap "rm -f '$tmpfile'" EXIT
        build_category_entries "$cat_id" "$tmpfile"
        [[ -s "$tmpfile" ]] || { notify-send "Spark" "No items in $cat_id"; exit 0; }
        show_menu "$cat_id" "$tmpfile"
        ;;
esac
