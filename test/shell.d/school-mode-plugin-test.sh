#!/bin/bash
#
# School mode and free time (shell/plugins/school-mode), after elgevan's
# omarchy-kids-menu: the pure logic under Node, the shortcut layer against a
# mocked hyprctl, and the wiring asserted from the sources.

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command node
require_command jq

plugin="$ROOT/shell/plugins/school-mode"
bash -n "$plugin/shortcut-policy" "$plugin/window-session" || fail "the helpers parse"
[[ -x $plugin/shortcut-policy && -x $plugin/window-session ]] || fail "the helpers are executable"
[[ -f $plugin/LICENSE ]] && grep -q 'MIT' "$plugin/LICENSE" || fail "the vendored code carries its MIT licence"
python3 - "$plugin/manifest.json" <<'PY' || fail "the manifest declares a menu, a bar widget, and a service under omarchy.school-mode"
import json, sys
m = json.load(open(sys.argv[1]))
assert m["id"] == "omarchy.school-mode" and m["keepLoaded"] is True
assert m["kinds"] == ["menu", "bar-widget", "service"], m["kinds"]
assert m["entryPoints"] == {"menu": "Menu.qml", "barWidget": "BarWidget.qml", "service": "Service.qml"}
PY
jq -e '(keys | sort) == ["apps", "style", "style.background", "style.theme"] and .apps.provider == "apps"' "$plugin/school-menu.jsonc" >/dev/null || fail "the school menu is the apps provider plus Style"
jq -e 'keys | length == 0' "$plugin/empty-menu.jsonc" >/dev/null || fail "the menu extension guard is empty"
pass "the school-mode plugin ships with its manifest, menus, helpers, and licence"

python3 - "$plugin/Service.qml" <<'PY' || fail "the service does not redeclare or re-emit a property's implicit change signal"
import pathlib
import re
import sys

source = pathlib.Path(sys.argv[1]).read_text()
properties = set(re.findall(r"^\s*(?:readonly\s+)?property\s+\S+\s+([A-Za-z_]\w*)", source, re.MULTILINE))
signals = set(re.findall(r"^\s*signal\s+([A-Za-z_]\w*)", source, re.MULTILINE))
duplicates = sorted(name for name in signals if name.endswith("Changed") and name[:-7] in properties)
reemitted = sorted(
    name for name in properties
    if re.search(rf"\broot\.{re.escape(name)}Changed\s*\(\s*\)", source)
)
assert not duplicates, f"duplicate property change signals: {duplicates}"
assert not reemitted, f"re-emitted property change signals: {reemitted}"
PY
pass "the school-mode service leaves property change signals to QML"

node - "$plugin/Allowlist.js" <<'NODE'
const assert = require("node:assert/strict")
const allowlist = require(process.argv[2])
assert.deepEqual(allowlist.normalizeIds(["obsidian", "obsidian.desktop", " Khan Academy ", ""]), ["Khan Academy", "obsidian"])
assert.deepEqual(
  allowlist.filterRows([{entry: {id: "chromium"}}, {entry: {id: "org.gnome.Nautilus"}}, {entry: {id: "omawrite.desktop"}}], ["chromium", "omawrite"]).map(r => r.entry.id),
  ["chromium", "omawrite.desktop"])
assert.equal(allowlist.contains(["Khan Academy"], "Khan Academy.desktop"), true)
NODE
node - "$plugin/ModeState.js" <<'NODE'
const assert = require("node:assert/strict")
const state = require(process.argv[2])
const school = state.parseStatus('{"enabled": true, "mode": "school", "modeReason": "schedule", "schoolApps": ["obsidian", "chromium"], "schoolUntil": "15:30", "schoolLabel": "School"}')
assert.equal(state.schoolMode(school), true)
assert.deepEqual(school.schoolApps, ["obsidian", "chromium"])
assert.equal(state.reasonLine(school), "School until 15:30")
assert.equal(state.schoolMode(state.parseStatus('{"enabled": false, "mode": "school"}')), false, "no screen time, no school mode")
assert.equal(state.schoolMode(state.parseStatus("not json")), false)
assert.equal(state.reasonLine(state.parseStatus('{"enabled": true, "mode": "free", "modeReason": "parent", "schoolUntil": "15:30"}')), "Free time, set by a parent until 15:30")
assert.equal(state.reasonLine(state.parseStatus('{"enabled": true, "mode": "school", "modeReason": "chosen"}')), "Chosen for today")
NODE
node - "$plugin/NotificationState.js" <<'NODE'
const assert = require("node:assert/strict")
const state = require(process.argv[2])
assert.deepEqual(state.parseState(""), {managed: false, restoreDnd: false})
assert.deepEqual(state.parseState(JSON.stringify({version: 1, managed: true, restoreDnd: true})), {managed: true, restoreDnd: true})
NODE
node - "$plugin/ShellIntegration.js" <<'NODE'
const assert = require("node:assert/strict")
const integration = require(process.argv[2])
const pluginId = "omarchy.school-mode", pillId = pluginId + ".mode", pillPath = "/usr/share/omarchy/shell/plugins/school-mode/ModePill.qml"
const config = { version: 1, bar: { layout: { left: [{id: "omarchy.menu", custom: "preserved"}, {id: "omarchy.workspaces"}, {id: pluginId}], center: [], right: [{id: "omarchy.tray"}, {id: "omarchy.audio"}] } }, plugins: [] }
let result = integration.activate(config, pluginId, pillId, pillPath, true)
assert.deepEqual(config.bar.layout.left.map(integration.entryId), [pluginId, "omarchy.workspaces"], "the plugin's button takes the menu's slot")
assert.equal(config.bar.layout.left[0].schoolMenuRestore.entry.custom, "preserved", "the stock entry is kept for the way back")
assert.equal(config.bar.layout.right[1].id, pillId, "the mode pill goes after the tray")
assert.deepEqual(config.disabledPlugins, ["omarchy.menu"], "the stock menu is off in school mode")
result = integration.activate(config, pluginId, pillId, pillPath, false)
assert.equal(config.disabledPlugins, undefined, "the stock menu is back on in free time")
config.bar.layout.left = config.bar.layout.left.filter(e => integration.entryId(e) !== pluginId)
integration.deactivate(config, pillId, result.restore)
assert.deepEqual(config.bar.layout.left.map(integration.entryId), ["omarchy.menu", "omarchy.workspaces"], "deactivation restores the stock slot")
NODE
node - "$plugin/SchoolBrowser.js" <<'NODE'
const assert = require("node:assert/strict")
const browser = require(process.argv[2])
assert.equal(browser.isBrowser("chromium.desktop"), true)
assert.equal(browser.isBrowser("firefox"), false)
assert.equal(browser.webAppUrl(["omarchy-launch-webapp", "https://www.khanacademy.org/"]), "https://www.khanacademy.org/")
assert.equal(browser.webAppUrl([], "omarchy-launch-webapp https://www.wikipedia.org/"), "https://www.wikipedia.org/")
assert.equal(browser.SEPARATE_PROFILE, false, "one browser profile for now")
assert.equal(browser.profileDir("/home/kid/"), "/home/kid/.local/share/omarchy-kids/chromium-school")
assert.deepEqual(browser.launchCommand("/home/kid"), ["uwsm-app", "--", "/usr/bin/chromium", "--user-data-dir=/home/kid/.local/share/omarchy-kids/chromium-school", "--no-first-run", "--no-default-browser-check", "--disable-sync", "--new-window"])
assert.equal(browser.launchCommand("/home/kid", "https://www.khanacademy.org/").pop(), "--app=https://www.khanacademy.org/")
NODE
pass "the mode, the allowlist, the bar swap, and the school browser behave"

# The shortcut layer against a mocked hyprctl: what it unbinds and rebinds,
# and that exit reloads the real configuration. The helpers lock with flock,
# which this Mac does not have.
if ! command -v flock >/dev/null; then
  pass "no flock here; skipping the shortcut layer run"
  exit 0
fi
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/run"
cat >"$tmp/bin/hyprctl" <<'SH'
#!/bin/bash
printf 'hyprctl %s\n' "$1" >>"$HYPR_CALLS"
if [[ $1 == eval ]]; then printf '%s\n' "$2" >"$HYPR_LUA"; fi
exit 0
SH
chmod +x "$tmp/bin/hyprctl"
export HYPR_CALLS="$tmp/calls" HYPR_LUA="$tmp/lua" XDG_RUNTIME_DIR="$tmp/run" OMARCHY_SCHOOL_HYPRCTL="$tmp/bin/hyprctl"
: >"$HYPR_CALLS"
out=$("$plugin/shortcut-policy" enter) || fail "enter succeeds" "$out"
[[ $(jq -r '.applied' <<<"$out") == true ]] || fail "enter reports the layer applied" "$out"
grep -q 'hl.unbind("SUPER + SHIFT + M")' "$HYPR_LUA" && grep -q 'hl.unbind("SUPER + SHIFT + S")' "$HYPR_LUA" || fail "Music and Google Maps are unbound in school mode" "$(cat "$HYPR_LUA")"
! grep -q 'SUPER + SHIFT + B' "$HYPR_LUA" || fail "the browser keys are left alone with one profile" "$(cat "$HYPR_LUA")"
grep -q 'hl.bind("SUPER + SPACE", hl.dsp.exec_cmd(\[\[omarchy-shell shell toggle omarchy.school-mode' "$HYPR_LUA" || fail "the menu key opens the filtered menu"
! grep -q 'SUPER + RETURN"' "$HYPR_LUA" || fail "the terminal stays bound for the parent"
[[ -f $tmp/run/omarchy-school-mode/shortcut-policy.active ]] || fail "the layer leaves its marker"
[[ $("$plugin/shortcut-policy" status | jq -r '.applied') == true ]] || fail "status sees the layer"
: >"$HYPR_CALLS"
"$plugin/shortcut-policy" enter >/dev/null
grep -q '^hyprctl reload$' "$HYPR_CALLS" || fail "a second enter reloads the real bindings first, so nothing accumulates" "$(<"$HYPR_CALLS")"
: >"$HYPR_CALLS"
out=$("$plugin/shortcut-policy" exit)
grep -q '^hyprctl reload$' "$HYPR_CALLS" && [[ ! -f $tmp/run/omarchy-school-mode/shortcut-policy.active ]] || fail "exit reloads the real configuration and drops the marker"
pass "the school shortcut layer is applied with hyprctl and undone with a reload"

grep -q '"/var/lib/omarchy/parent/" + userName + "/time/status.json"' "$plugin/Service.qml" || fail "the service reads the mode from the daemon's status.json"
grep -q 'readonly property bool schoolMode: childInstall && timeEnabled && mode === "school"' "$plugin/Service.qml" || fail "school mode needs a child install with screen time on"
grep -q 'omarchy-profile-child && echo child || echo default' "$plugin/Service.qml" || fail "the service asks whether this is a child install"
grep -q 'ShellIntegration.activate(config, root.pluginId, root.modePillId, root.modePillPath, root.schoolMode)' "$plugin/Service.qml" || fail "the service takes the menu slot and places the pill"
grep -q 'serviceFor("omarchy.school-mode")' "$plugin/Menu.qml" && grep -q '"/school-menu.jsonc"' "$plugin/Menu.qml" || fail "the menu wrapper filters by the service in school mode"
grep -q 'if (SchoolBrowser.SEPARATE_PROFILE) {' "$plugin/Menu.qml" && grep -q 'var SEPARATE_PROFILE = false' "$plugin/SchoolBrowser.js" || fail "the school profile waits behind its flag; one profile for now"
grep -q '\[root.clientPath, "--password-stdin", "mode", mode\]' "$plugin/Panel.qml" && grep -q 'error === "parent_required"' "$plugin/Panel.qml" || fail "the panel switches through the daemon and asks for the parent password when it must"
grep -q 'onRunningChanged: if (!running && !launched) root.handleModeReply("")' "$plugin/Panel.qml" && grep -q 'modeProc.launched = false' "$plugin/Panel.qml" || fail "a client that could not start does not leave the panel waiting"
grep -q 'moduleName: "omarchy.school-mode.mode"' "$plugin/ModePill.qml" && grep -q 'moduleName: "omarchy.school-mode"' "$plugin/BarWidget.qml" || fail "the pill and the button carry their ids"
grep -q 'omarchy.school-mode' "$ROOT/install/user/screen-time.sh" && grep -q 'omarchy.school-mode' "$ROOT/bin/omarchy-parent-time" || fail "a child install's bar gets the plugin's button"
grep -q '| School mode   | `omarchy.school-mode`' "$ROOT/shell/plugins/README.md" || fail "the plugin is listed"
pass "school mode is wired from the daemon's status through the menu, the shortcuts, the windows, and the bar"
