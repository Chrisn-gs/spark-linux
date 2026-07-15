#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════
# scan-apps.sh — Scan .desktop files & import into Spark
# ═══════════════════════════════════════════════════════
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="${SPARK_CONFIG:-$PROJECT_DIR/config/config.json}"

if ! command -v jq &>/dev/null; then
    notify-send -u critical "Spark" "jq is required"
    exit 1
fi

# ── scan .desktop dirs ────────────────────────────────
DESKTOP_DIRS=(
    "/usr/share/applications"
    "$HOME/.local/share/applications"
    "/var/lib/flatpak/exports/share/applications"
    "$HOME/.local/share/flatpak/exports/share/applications"
)

declare -A SEEN
apps=()

for dir in "${DESKTOP_DIRS[@]}"; do
    [[ -d "$dir" ]] || continue
    for f in "$dir"/*.desktop; do
        [[ -f "$f" ]] || continue
        # Skip NoDisplay/Hidden
        if grep -q '^NoDisplay=true' "$f" 2>/dev/null || grep -q '^Hidden=true' "$f" 2>/dev/null; then
            continue
        fi
        name="$(grep -m1 '^Name=' "$f" | cut -d= -f2-)"
        exec_line="$(grep -m1 '^Exec=' "$f" | cut -d= -f2- | sed 's/ *%[fFuUdDnNickvm]//g')"
        icon="$(grep -m1 '^Icon=' "$f" | cut -d= -f2-)"
        [[ -z "$name" || -z "$exec_line" ]] && continue
        # Dedup by name
        [[ -n "${SEEN[$name]:-}" ]] && continue
        SEEN["$name"]=1
        apps+=("${name}|${exec_line}|${icon}|$(basename "$f" .desktop)")
    done
done

if [[ ${#apps[@]} -eq 0 ]]; then
    notify-send "Spark" "No applications found"
    exit 0
fi

# ── show in wofi for selection ────────────────────────
entries=""
for app in "${apps[@]}"; do
    name="$(echo "$app" | cut -d'|' -f1)"
    entries+="${name}"$'\n'
done

chosen_names="$(printf '%s' "$entries" | wofi \
    --dmenu \
    --prompt "Select apps to import" \
    --width 500 --height 500 \
    --matching fuzzy \
    --multi-select \
    --conf "$PROJECT_DIR/themes/wofi.conf" \
    --style "$PROJECT_DIR/themes/wofi.css" \
    2>/dev/null)" || exit 0

[[ -z "$chosen_names" ]] && exit 0

# ── pick target category ──────────────────────────────
cat_entries=""
while IFS= read -r cat; do
    id="$(echo "$cat" | jq -r '.id')"
    name="$(echo "$cat" | jq -r '.name')"
    icon="$(echo "$cat" | jq -r '.icon')"
    cat_entries+="${icon} ${name}|${id}"$'\n'
done < <(jq -c '.categories[]' "$CONFIG_FILE")

target="$(printf '%s' "$cat_entries" | wofi \
    --dmenu \
    --prompt "Import to category" \
    --width 300 --height 300 \
    --conf "$PROJECT_DIR/themes/wofi.conf" \
    --style "$PROJECT_DIR/themes/wofi.css" \
    2>/dev/null)" || exit 0

cat_id="$(echo "$target" | awk -F'|' '{print $2}')"
[[ -z "$cat_id" ]] && exit 0

# ── import selected apps ──────────────────────────────
imported=0
while IFS= read -r chosen; do
    [[ -z "$chosen" ]] && continue
    for app in "${apps[@]}"; do
        app_name="$(echo "$app" | cut -d'|' -f1)"
        if [[ "$app_name" == "$chosen" ]]; then
            exec_cmd="$(echo "$app" | cut -d'|' -f2)"
            # Add to config via jq
            tmp="$(mktemp)"
            jq --arg cid "$cat_id" --arg n "$app_name" --arg c "$exec_cmd" '
                .categories |= map(
                    if .id == $cid then
                        .items += [{"name": $n, "type": "app", "command": $c}]
                    else . end
                )
            ' "$CONFIG_FILE" > "$tmp" && mv "$tmp" "$CONFIG_FILE"
            imported=$((imported + 1))
            break
        fi
    done
done <<< "$chosen_names"

notify-send "Spark" "Imported ${imported} app(s) into ${cat_id}"
echo "Imported ${imported} app(s) into ${cat_id}"
