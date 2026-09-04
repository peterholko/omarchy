#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const idle = requireFromRoot('shell/plugins/services/idle/IdleModel.js')

assertEqual(idle.secondsFromConfig('42.9', 10), 42, 'idle floors configured seconds')
assertEqual(idle.secondsFromConfig('-1', 10), 10, 'idle rejects negative seconds')
assertEqual(idle.secondsFromConfig('nope', 10), 10, 'idle rejects invalid seconds')

assertDeepEqual(idle.eventParts({ data: 'a,b,c' }, 2), ['a', 'b', 'c'], 'idle parses raw event data')
assertDeepEqual(
  idle.eventParts({ parse: function(count) { return ['parsed', count] } }, 4),
  ['parsed', 4],
  'idle prefers event parser when available'
)

assertDeepEqual(
  idle.screensaverWindowsAfter({ a: true }, 'b', true),
  { windows: { a: true, b: true }, count: 2 },
  'idle adds visible screensaver windows'
)
assertDeepEqual(
  idle.screensaverWindowsAfter({ a: true, b: true }, 'a', false),
  { windows: { b: true }, count: 1 },
  'idle removes closed screensaver windows'
)
assertDeepEqual(
  idle.screensaverWindowsAfter({ a: true }, '', false),
  { windows: { a: true }, count: 1 },
  'idle leaves screensaver windows unchanged without an address'
)
JS

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

test_home="$test_tmp/home"
mkdir -p "$test_home"

HOME="$test_home" "$ROOT/bin/omarchy-toggle-idle" stay-awake >/dev/null
[[ -f $test_home/.local/state/omarchy/indicators/stay-awake ]] || fail "Stay Awake toggle persists enabled state"

HOME="$test_home" "$ROOT/bin/omarchy-toggle-idle" allow-idle >/dev/null
[[ ! -f $test_home/.local/state/omarchy/indicators/stay-awake ]] || fail "Stay Awake toggle persists disabled state"

if rg -q 'omarchy-shell' "$ROOT/bin/omarchy-toggle-idle"; then
  fail "Stay Awake toggle avoids reentrant shell IPC"
fi

pass "Stay Awake toggle persists state without reentrant shell IPC"

# A child install has no screensaver: the shell locks at the screensaver's
# time, the launcher refuses unless a parent forces it, and the menu keeps the
# screensaver rows for the parent's own machines.
service="$ROOT/shell/plugins/services/idle/Service.qml"
grep -q 'omarchy-profile-child && echo child || echo default' "$service" && grep -q 'childInstall ? firstIdleTimeoutSeconds : lockTimeoutSeconds' "$service" || fail "a child install locks at the screensaver's time instead of showing one"
grep -q 'if (root.childInstall) logEvent("screensaver-skipped"' "$service" || fail "a child install never launches the screensaver"
grep -q 'if omarchy-profile-child && \[\[ \$1 != "force" \]\]; then' "$ROOT/bin/omarchy-launch-screensaver" || fail "omarchy-launch-screensaver refuses on a child install unless a parent forces it"
menu="$ROOT/default/omarchy/omarchy-menu.jsonc"
for id in system.screensaver trigger.toggle.screensaver style.screensaver.text style.screensaver.image style.screensaver.default; do
  grep -q "\"$id\": {.*\"when\":\"! omarchy-profile-child\"" "$menu" || fail "the menu hides $id on a child install"
done
pass "a child install has no screensaver: idle goes straight to the lock"
