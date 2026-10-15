#!/bin/bash
# herdr event hook (pane.agent_status_changed): a skyland-cyberdeck message when
# an agent is done or waits for you (blocked / waiting). The event JSON is in
# HERDR_PLUGIN_EVENT_JSON; the last one is kept in the plugin state dir.
DECK="${SKYLAND_CYBERDECK:-$HOME/code/hyperland/skyland-cyberdeck/.build/release/skyland-cyberdeck}"
[[ -x "$DECK" ]] || exit 0
[[ -n "$HERDR_PLUGIN_STATE_DIR" ]] && printf '%s\n' "$HERDR_PLUGIN_EVENT_JSON" > "$HERDR_PLUGIN_STATE_DIR/last-event.json"

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
# the pane you are looking at: no popup (herdr also only sounds for the background)
# (front app from skyland's CLI: lsappinfo has no front app for background processes)
WM="${SKYLAND_CLI:-$HOME/code/hyperland/skyland/.build/debug/aerospace}"
if [[ "$focused" == true && -x "$WM" ]] \
    && [[ "$("$WM" list-windows --focused --format '%{app-bundle-id}' </dev/null 2>/dev/null)" == com.mitchellh.ghostty ]]; then
    exit 0
fi

case "$status" in
    done) title="${agent:-agent} finished" ;;
    blocked | waiting) title="${agent:-agent} needs you" ;;
    *) exit 0 ;;
esac
"$DECK" notify -a com.mitchellh.ghostty -t "$title" -s "${where:-herdr}" -b "$detail" >/dev/null 2>&1 &
