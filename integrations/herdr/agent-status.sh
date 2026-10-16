#!/bin/bash
# herdr event hook (pane.agent_status_changed): a skyland-cyberdeck message when
# an agent is done or waits for you (blocked / waiting). The event JSON is in
# HERDR_PLUGIN_EVENT_JSON; the last one is kept in the plugin state dir.
# herdr runs hooks with a short PATH: add the usual install places
PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"
DECK="${SKYLAND_CYBERDECK:-$(command -v skyland-cyberdeck)}"
[[ -x "$DECK" ]] || exit 0
STATE="${HERDR_PLUGIN_STATE_DIR:-${TMPDIR:-/tmp}/skyland-cyberdeck-herdr}"
mkdir -p "$STATE"
printf '%s\n' "$HERDR_PLUGIN_EVENT_JSON" > "$STATE/last-event.json"
printf '%s %s\n' "$(date '+%F %T')" "$HERDR_PLUGIN_EVENT_JSON" >> "$STATE/events.log"
tail -n 300 "$STATE/events.log" > "$STATE/events.log.tmp" && mv "$STATE/events.log.tmp" "$STATE/events.log"

# status / agent / workspace / pane title, wherever they sit in the event
IFS=$'\t' read -r status agent where detail < <(printf '%s' "$HERDR_PLUGIN_EVENT_JSON" | /usr/bin/python3 -c '
import json, sys
try:
    event = json.load(sys.stdin)
except ValueError:
    sys.exit(0)
found = {}
def walk(node):
    if isinstance(node, dict):
        for key, value in node.items():
            if isinstance(value, (str, int, float)) and key not in found:
                found[key] = str(value)
            walk(value)
    elif isinstance(node, list):
        for value in node:
            walk(value)
walk(event)
pick = lambda *keys: next((found[k] for k in keys if found.get(k)), "")
print("\t".join([
    pick("agent_status", "status", "state"),
    pick("display_agent", "agent", "agent_name"),
    pick("workspace_label", "workspace_name", "workspace", "label"),
    pick("terminal_title_stripped", "terminal_title", "title"),
]))
')

# workspace label, pane title and focus from herdr (the event only has ids)
HERDR="${HERDR_BIN_PATH:-herdr}"
pane_id="$(printf '%s' "$HERDR_PLUGIN_EVENT_JSON" | /usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin).get("data", {}).get("pane_id", ""))' 2>/dev/null)"
focused=false
if [[ -n "$pane_id" ]]; then
    IFS=$'\t' read -r where detail focused < <("$HERDR" pane get "$pane_id" 2>/dev/null | /usr/bin/python3 -c '
import json, subprocess, sys
try:
    pane = json.load(sys.stdin)["result"]["pane"]
except (ValueError, KeyError):
    sys.exit(0)
label = ""
try:
    out = subprocess.run([sys.argv[1], "workspace", "get", pane["workspace_id"]], capture_output=True, text=True, timeout=3).stdout
    label = json.loads(out)["result"]["workspace"].get("label", "")
except Exception:
    pass
print("\t".join([label, pane.get("terminal_title_stripped", ""), str(pane.get("focused", False)).lower()]))
' "$HERDR")
fi
case "$status" in
    done) kind=done title="${agent:-agent} finished" ;;
    blocked | waiting) kind=request title="${agent:-agent} needs you" ;;
    *) exit 0 ;;
esac

# the terminal herdr runs in: skyland's [terminal] app, Ghostty by default
WM="${SKYLAND_CLI:-$(command -v skyland)}"
term="$([[ -x "$WM" ]] && "$WM" config terminal app 2>/dev/null)"
term="${term:-Ghostty}"
term_id="$(osascript -e "id of application \"$term\"" 2>/dev/null || echo com.mitchellh.ghostty)"
# the pane you are looking at: no popup (herdr also only sounds for the background)
# (front app from skyland's CLI: lsappinfo has no front app for background processes)
if [[ "$focused" == true && -x "$WM" ]] \
    && [[ "$("$WM" list-windows --focused --format '%{app-bundle-id}' </dev/null 2>/dev/null)" == "$term_id" ]]; then
    exit 0
fi

# herdr flaps done -> working -> done at the end of a turn: one message per pane
# and kind, then quiet for DEBOUNCE seconds
DEBOUNCE=60
stamp="$STATE/notified-$(printf '%s' "${pane_id:-unknown}" | tr -c 'A-Za-z0-9' _)-$kind"
now=$(date +%s)
if [[ -f "$stamp" ]] && (( now - $(cat "$stamp") < DEBOUNCE )); then
    exit 0
fi
echo "$now" > "$stamp"
"$DECK" notify -a "$term_id" -t "$title" -s "${where:-herdr}" -b "$detail" >/dev/null 2>&1 &
