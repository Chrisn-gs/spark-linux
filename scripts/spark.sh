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

# ── ensure jq available ───────────────────────────────
if ! command -v jq &>/dev/null; then
    notify-send -u critical "Spark" "jq is required. Install: sudo pacman -S jq"
    exit 1
fi
if ! command -v wofi &>/dev/null; then
    notify-send -u critical "Spark" "wofi is required. Install: sudo pacman -S wofi"
    exit 1
fi

# ── ensure data dir ───────────────────────────────────
mkdir -p "$HISTORY_DIR"
[[ -f "$RECENT_FILE" ]] || echo '[]' > "$RECENT_FILE"

# ── helpers ────────────────────────────────────────────
log_recent() {
    # $1=name $2=type $3=command
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
    # $1=type  $2=command  $3=name
    log_recent "$3" "$1" "$2"
    case "$1" in
        app)
            # Try desktop entry first, then direct command
            if gtk-launch "$2" 2>/dev/null; then
                return
            fi
            setsid "$2" &>/dev/null &
            ;;
        url)
            xdg-open "$2" &>/dev/null &
            ;;
        folder)
            xdg-open "$2" &>/dev/null &
            ;;
        script)
            setsid bash -c "$2" &>/dev/null &
            ;;
        *)
            setsid "$2" &>/dev/null &
            ;;
    esac
}

show_menu() {
    # $1=title  $2=entries (newline-separated "name\0type\0command")
    local title="$1"
    shift
    local chosen
    chosen="$(printf '%s' "$@" | wofi \
        --dmenu \
        --prompt "$title" \
        --width 450 --height 400 \
        --matching fuzzy \
        --sort-by=alphabetical \
        --allow-markup \
        --conf "$PROJECT_DIR/themes/wofi.conf" \
        --style "$PROJECT_DIR/themes/wofi.css" \
        2>/dev/null)" || exit 0

    [[ -z "$chosen" ]] && exit 0

    # Parse: format is "icon name |type|command"
    local type command name
    type="$(echo "$chosen" | awk -F'|' '{print $2}')"
    command="$(echo "$chosen" | awk -F'|' '{print $3}')"
    name="$(echo "$chosen" | awk -F'|' '{print $1}' | sed 's/^[^ ]* //')"
    launch_item "$type" "$command" "$name"
}

# ── build category menu entries ────────────────────────
build_category_entries() {
    local cat_id="$1"
    local entries=""
    local count=0

    while IFS= read -r item; do
        count=$((count + 1))
        local name type cmd icon
        name="$(echo "$item" | jq -r '.name')"
        type="$(echo "$item" | jq -r '.type')"
        cmd="$(echo "$item" | jq -r '.command')"
        icon="$(case "$type" in
            app)    echo " " ;;
            url)    echo " " ;;
            folder) echo " " ;;
            script) echo ">" ;;
            *)      echo " " ;;
        esac)"
        entries+="${icon} ${name}|${type}|${cmd}"$'\n'
    done < <(jq -r --arg id "$cat_id" '
        .categories[] | select(.id == $id) | .items[]
    ' "$CONFIG_FILE")

    echo -n "$entries"
}

# ── build all-items for global search ──────────────────
build_all_entries() {
    local entries=""
    while IFS= read -r cat; do
        local cat_name
        cat_name="$(echo "$cat" | jq -r '.name')"
        while IFS= read -r item; do
            local name type cmd icon
            name="$(echo "$item" | jq -r '.name')"
            type="$(echo "$item" | jq -r '.type')"
            cmd="$(echo "$item" | jq -r '.command')"
            icon="$(case "$type" in
                app)    echo " " ;;
                url)    echo " " ;;
                folder) echo " " ;;
                script) echo ">" ;;
                *)      echo " " ;;
            esac)"
            entries+="${icon} ${name} [${cat_name}]|${type}|${cmd}"$'\n'
        done < <(echo "$cat" | jq -c '.items[]')
    done < <(jq -c '.categories[]' "$CONFIG_FILE")
    echo -n "$entries"
}

# ── build recent entries ───────────────────────────────
build_recent_entries() {
    local entries=""
    while IFS= read -r item; do
        local name type cmd icon
        name="$(echo "$item" | jq -r '.name')"
        type="$(echo "$item" | jq -r '.type')"
        cmd="$(echo "$item" | jq -r '.command')"
        icon="$(case "$type" in
            app)    echo " " ;;
            url)    echo " " ;;
            folder) echo " " ;;
            script) echo ">" ;;
            *)      echo " " ;;
        esac)"
        entries+="${icon} ${name}|${type}|${cmd}"$'\n'
    done < <(jq -c '.[]' "$RECENT_FILE")
    echo -n "$entries"
}

# ── category list mode ─────────────────────────────────
show_category_list() {
    local entries=""
    while IFS= read -r cat; do
        local id name icon hotkey count
        id="$(echo "$cat" | jq -r '.id')"
        name="$(echo "$cat" | jq -r '.name')"
        icon="$(echo "$cat" | jq -r '.icon')"
        hotkey="$(echo "$cat" | jq -r '.hotkey')"
        count="$(echo "$cat" | jq -r '.items | length')"
        entries+="${icon} ${name} (${count}) — ${hotkey}|cat|${id}"$'\n'
    done < <(jq -c '.categories[]' "$CONFIG_FILE")

    local chosen
    chosen="$(printf '%s' "$entries" | wofi \
        --dmenu \
        --prompt "Spark" \
        --width 400 --height 350 \
        --matching fuzzy \
        --allow-markup \
        --conf "$PROJECT_DIR/themes/wofi.conf" \
        --style "$PROJECT_DIR/themes/wofi.css" \
        2>/dev/null)" || exit 0

    [[ -z "$chosen" ]] && exit 0

    local cat_id
    cat_id="$(echo "$chosen" | awk -F'|' '{print $3}')"
    local items
    items="$(build_category_entries "$cat_id")"
    [[ -z "$items" ]] && exit 0
    show_menu "$cat_id" "$items"
}

# ── main ───────────────────────────────────────────────
case "${1:---list}" in
    --list|-l)
        show_category_list
        ;;
    --search|-s)
        items="$(build_all_entries)"
        [[ -z "$items" ]] && exit 0
        show_menu "Search All" "$items"
        ;;
    --recent|-r)
        items="$(build_recent_entries)"
        if [[ -z "$items" ]]; then
            notify-send "Spark" "No recent launches"
            exit 0
        fi
        show_menu "Recent" "$items"
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
        # Direct category launch
        cat_id="$1"
        if ! jq -e --arg id "$cat_id" '.categories[] | select(.id == $id)' "$CONFIG_FILE" &>/dev/null; then
            notify-send -u critical "Spark" "Category '$cat_id' not found"
            exit 1
        fi
        items="$(build_category_entries "$cat_id")"
        [[ -z "$items" ]] && exit 0
        show_menu "$cat_id" "$items"
        ;;
esac
