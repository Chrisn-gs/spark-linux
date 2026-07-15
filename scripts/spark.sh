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

TAB=$'\t'

# ── find icon file on disk for a given icon name ───────
# Searches hicolor theme for the best match
_icon_file() {
    local name="$1"
    local size="${2:-24}"

    # If it's already an absolute path and exists, use it
    [[ -f "$name" ]] && echo "$name" && return

    # Search icon theme directories (prefer scalable, then exact size, then 48)
    local -a search_sizes=("scalable" "${size}x${size}" "48x48" "32x32" "24x24" "16x16" "128x128")
    local -a search_dirs=("/usr/share/icons/hicolor" "/usr/share/icons/Adwaita" "/usr/share/icons/AdwaitaLegacy" "/usr/share/pixmaps")

    for dir in "${search_dirs[@]}"; do
        [[ -d "$dir" ]] || continue
        # Check pixmaps first (flat directory)
        if [[ "$dir" == *"pixmaps"* ]]; then
            for ext in png svg xpm; do
                if [[ -f "$dir/${name}.${ext}" ]]; then
                    echo "$dir/${name}.${ext}"
                    return
                fi
            done
            continue
        fi
        for sz in "${search_sizes[@]}"; do
            for subdir in apps devices places legacy mimetypes; do
                for ext in png svg; do
                    local path="$dir/$sz/$subdir/${name}.${ext}"
                    if [[ -f "$path" ]]; then
                        echo "$path"
                        return
                    fi
                done
            done
        done
    done

    # Fallback: return empty (no icon)
    echo ""
}

# ── look up Icon= from .desktop file ───────────────────
_icon_for_app() {
    local cmd="$1"

    for dir in /usr/share/applications ~/.local/share/applications; do
        [[ -d "$dir" ]] || continue
        for f in "$dir"/*.desktop; do
            [[ -f "$f" ]] || continue
            local exec_line
            exec_line="$(grep -m1 '^Exec=' "$f" 2>/dev/null | cut -d= -f2- | sed 's/ *%[fFuUdDnNickvm]//g')"
            # Match exec_line starts with cmd, or contains /cmd, or desktop name matches
            local desktop_name
            desktop_name="$(basename "$f" .desktop)"
            if [[ "$exec_line" == "$cmd"* ]] || [[ "$exec_line" == *"/$cmd "* ]] || \
               [[ "$exec_line" == *"/$cmd" ]] || [[ "$desktop_name" == "$cmd" ]]; then
                local icon_name
                icon_name="$(grep -m1 '^Icon=' "$f" 2>/dev/null | cut -d= -f2-)"
                if [[ -n "$icon_name" ]]; then
                    local icon_path
                    icon_path="$(_icon_file "$icon_name")"
                    [[ -n "$icon_path" ]] && echo "$icon_path" && return
                fi
            fi
        done
    done

    echo ""
}

# ── icon path for an entry ─────────────────────────────
icon_for() {
    local type="$1" cmd="$2"
    local icon_path=""

    case "$type" in
        app)    icon_path="$(_icon_for_app "$cmd")" ;;
        url)    icon_path="$(_icon_file "web-browser")" ;;
        folder) icon_path="$(_icon_file "folder")" ;;
        script) icon_path="$(_icon_file "utilities-terminal")" ;;
    esac

    # Fallback
    [[ -z "$icon_path" ]] && icon_path="$(_icon_file "application-x-executable")"
    [[ -z "$icon_path" ]] && icon_path="$(_icon_file "exec")"

    echo "$icon_path"
}

# ── format a wofi entry with image ─────────────────────
# wofi dmenu image format: img:/path/to/file  text
format_entry() {
    local name="$1" type="$2" cmd="$3"
    local icon_path
    icon_path="$(icon_for "$type" "$cmd")"

    if [[ -n "$icon_path" ]]; then
        echo "img:${icon_path}  ${name}${TAB}${type}${TAB}${cmd}"
    else
        echo "${name}${TAB}${type}${TAB}${cmd}"
    fi
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
show_menu() {
    local prompt="$1"
    local entries_file="$2"

    local chosen
    chosen="$(wofi \
        --dmenu \
        --prompt "$prompt" \
        --width 450 --height 400 \
        --allow-images \
        --conf "$PROJECT_DIR/themes/wofi.conf" \
        --style "$PROJECT_DIR/themes/wofi.css" \
        < "$entries_file" 2>/dev/null)" || exit 0

    [[ -z "$chosen" ]] && exit 0

    # Strip img: prefix if present, then parse tabs
    local clean
    clean="$(echo "$chosen" | sed 's|^img:[^ ]*  ||')"
    local display type cmd
    display="$(echo "$clean" | cut -d"$TAB" -f1)"
    type="$(echo "$clean" | cut -d"$TAB" -f2)"
    cmd="$(echo "$clean" | cut -d"$TAB" -f3)"

    [[ -z "$type" || -z "$cmd" ]] && exit 1
    launch_item "$type" "$cmd" "$display"
}

# ── build entries ──────────────────────────────────────
build_category_entries() {
    local cat_id="$1"
    local tmpfile="$2"

    while IFS="$TAB" read -r name type cmd; do
        format_entry "$name" "$type" "$cmd"
    done < <(jq -r --arg id "$cat_id" '
        .categories[] | select(.id == $id) | .items[] |
        "\(.name)\t\(.type)\t\(.command)"
    ' "$CONFIG_FILE") > "$tmpfile"
}

build_all_entries() {
    local tmpfile="$1"

    while IFS="$TAB" read -r name type cmd; do
        format_entry "$name" "$type" "$cmd"
    done < <(jq -r '
        .categories[] | .items[] |
        "\(.name)\t\(.type)\t\(.command)"
    ' "$CONFIG_FILE") > "$tmpfile"
}

build_recent_entries() {
    local tmpfile="$1"

    while IFS="$TAB" read -r name type cmd; do
        format_entry "$name" "$type" "$cmd"
    done < <(jq -r '
        .[] | "\(.name)\t\(.type)\t\(.command)"
    ' "$RECENT_FILE") > "$tmpfile"
}

# ── show category list ─────────────────────────────────
show_category_list() {
    local tmpfile
    tmpfile="$(mktemp)"
    trap "rm -f '$tmpfile'" EXIT

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

    > "$tmpfile"
    while IFS="$TAB" read -r id name count hotkey; do
        local icon_path="${cat_icons[$id]:-application-x-executable}"
        icon_path="$(_icon_file "$icon_path")"
        if [[ -n "$icon_path" ]]; then
            echo "img:${icon_path}  ${name} (${count}) — ${hotkey}${TAB}cat${TAB}${id}"
        else
            echo "${name} (${count}) — ${hotkey}${TAB}cat${TAB}${id}"
        fi
    done < <(jq -r '
        .categories[] |
        "\(.id)\t\(.name)\t\(.items | length)\t\(.hotkey)"
    ' "$CONFIG_FILE") >> "$tmpfile"

    local chosen
    chosen="$(wofi \
        --dmenu \
        --prompt "Spark" \
        --width 400 --height 350 \
        --allow-images \
        --conf "$PROJECT_DIR/themes/wofi.conf" \
        --style "$PROJECT_DIR/themes/wofi.css" \
        < "$tmpfile" 2>/dev/null)" || exit 0

    [[ -z "$chosen" ]] && exit 0

    local clean
    clean="$(echo "$chosen" | sed 's|^img:[^ ]*  ||')"
    local cat_id
    cat_id="$(echo "$clean" | cut -d"$TAB" -f3)"

    local items_file
    items_file="$(mktemp)"
    trap "rm -f '$tmpfile' '$items_file'" EXIT
    build_category_entries "$cat_id" "$items_file"

    [[ -s "$items_file" ]] || { notify-send "Spark" "No items in $cat_id"; exit 0; }
    show_menu "$cat_id" "$items_file"
}

# ── main ───────────────────────────────────────────────
case "${1:---list}" in
    --list|-l)       show_category_list ;;
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
    --scan)          exec "$SCRIPT_DIR/scan-apps.sh" ;;
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
