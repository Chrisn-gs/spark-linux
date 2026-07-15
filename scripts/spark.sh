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

# ── ensure data dir ───────────────────────────────────
mkdir -p "$HISTORY_DIR"
[[ -f "$RECENT_FILE" ]] || echo '[]' > "$RECENT_FILE"

# Kill any existing spark wofi instance before opening a new one
pkill -f "wofi.*spark-linux" 2>/dev/null || true

# ── delimiter (tab) ───────────────────────────────────
# Format per line: "display_name<TAB>type<TAB>command"
DELIM=$'\t'

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
    ' "$RECENT_FILE" > "$tmp" && mv "$tmp" "$RECENT_FILE" &
}

launch_item() {
    local type="$1" cmd="$2" name="$3"
    log_recent "$name" "$type" "$cmd"
    case "$type" in
        app)    setsid "$cmd" &>/dev/null & ;;
        url)    xdg-open "$cmd" &>/dev/null & ;;
        folder) xdg-open "$cmd" &>/dev/null & ;;
        script) setsid bash -c "$cmd" &>/dev/null & ;;
        *)      setsid "$cmd" &>/dev/null & ;;
    esac
}

# ── show wofi menu from a temp file ────────────────────
# $1=prompt  $2=tmpfile path (lines: display<TAB>type<TAB>command)
show_menu() {
    local prompt="$1"
    local entries_file="$2"

    local chosen
    chosen="$(GTK_IM_MODULE=xim wofi \
        --dmenu \
        --prompt "$prompt" \
        --width 450 --height 400 \
        --matching fuzzy \
        --sort-by=alphabetical \
        --allow-markup \
        --conf "$PROJECT_DIR/themes/wofi.conf" \
        --style "$PROJECT_DIR/themes/wofi.css" \
        < "$entries_file" 2>/dev/null)" || exit 0

    [[ -z "$chosen" ]] && exit 0

    # Parse tab-separated: display<TAB>type<TAB>command
    local display type cmd
    display="$(echo "$chosen" | cut -f1)"
    type="$(echo "$chosen" | cut -f2)"
    cmd="$(echo "$chosen" | cut -f3)"

    [[ -z "$type" || -z "$cmd" ]] && exit 1
    launch_item "$type" "$cmd" "$display"
}

# ── type icon ──────────────────────────────────────────
type_icon() {
    case "$1" in
        app)    echo " " ;;
        url)    echo " " ;;
        folder) echo " " ;;
        script) echo ">" ;;
        *)      echo " " ;;
    esac
}

# ── build category entries to tmpfile ──────────────────
build_category_entries() {
    local cat_id="$1"
    local tmpfile="$2"

    jq -r --arg id "$cat_id" '
        .categories[] | select(.id == $id) | .items[] |
        "\(.name)\t\(.type)\t\(.command)"
    ' "$CONFIG_FILE" > "$tmpfile"
}

# ── build all entries for global search ────────────────
build_all_entries() {
    local tmpfile="$1"

    jq -r '
        .categories[] | .items[] |
        "\(.name)\t\(.type)\t\(.command)"
    ' "$CONFIG_FILE" > "$tmpfile"
}

# ── build recent entries ───────────────────────────────
build_recent_entries() {
    local tmpfile="$1"

    jq -r '
        .[] | "\(.name)\t\(.type)\t\(.command)"
    ' "$RECENT_FILE" > "$tmpfile"
}

# ── show category list ─────────────────────────────────
show_category_list() {
    local tmpfile
    tmpfile="$(mktemp)"
    trap "rm -f '$tmpfile'" EXIT

    jq -r '
        .categories[] |
        "\(.icon) \(.name) (\(.items | length)) — \(.hotkey)\tcat\t\(.id)"
    ' "$CONFIG_FILE" > "$tmpfile"

    local chosen
    chosen="$(GTK_IM_MODULE=xim wofi \
        --dmenu \
        --prompt "Spark" \
        --width 400 --height 350 \
        --matching fuzzy \
        --allow-markup \
        --conf "$PROJECT_DIR/themes/wofi.conf" \
        --style "$PROJECT_DIR/themes/wofi.css" \
        < "$tmpfile" 2>/dev/null)" || exit 0

    [[ -z "$chosen" ]] && exit 0

    local cat_id
    cat_id="$(echo "$chosen" | cut -f3)"

    # Now show items in that category
    local items_file
    items_file="$(mktemp)"
    trap "rm -f '$tmpfile' '$items_file'" EXIT
    build_category_entries "$cat_id" "$items_file"

    if [[ ! -s "$items_file" ]]; then
        notify-send "Spark" "No items in $cat_id"
        exit 0
    fi

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
