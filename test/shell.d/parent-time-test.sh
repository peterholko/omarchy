#!/bin/bash
#
# `omarchy-parent time` switches screen time on and off for the kid account and
# tunes it. It lives in omarchy-parent-time, which omarchy-parent dispatches
# to; the functions run extracted from it against a scratch tree, with
# systemctl, omarchy-apply-lock, and visudo stubbed, and the real
# omarchy-parent-quiz.

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

parent="$ROOT/bin/omarchy-parent"
parent_time="$ROOT/bin/omarchy-parent-time"
test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
mkdir -p "$stub_bin" "$test_tmp/sudoers.d" "$test_tmp/units"
export CALLS="$test_tmp/calls"
for stub in systemctl omarchy-apply-lock; do
  cat >"$stub_bin/$stub" <<SH
#!/bin/bash
printf '$stub %s\\n' "\$*" >>"\$CALLS"
SH
done
printf '#!/bin/bash\nexit 0\n' >"$stub_bin/visudo"
chmod +x "$stub_bin"/*
export PATH="$stub_bin:$ROOT/bin:$PATH"

export OMARCHY_SUDOERS_DIR="$test_tmp/sudoers.d" OMARCHY_SYSTEM_UNIT_DIR="$test_tmp/units" \
  OMARCHY_PARENT_STATE_DIR="$test_tmp/state" OMARCHY_PATH="$ROOT"

# Load the real functions: the shared helper for the sudoers installer, then
# the command's paths and its screen-time section.
source "$ROOT/install/helpers/parent.sh"
eval "$(sed -n '/^STATE_ROOT=/,/^SYSTEM_UNIT_DIR=/p' "$parent_time")"
eval "$(sed -n '/^fail() {/,/^}/p' "$parent_time")"
eval "$(sed -n '/^# --- screen time ---$/,/^# --- end screen time ---$/p' "$parent_time")"
systemd_running() { [[ ${STUB_SYSTEMD:-running} == running ]]; }

: >"$CALLS"
time_on kid >/dev/null
dir="$test_tmp/state/kid/time"
[[ -f $dir/enabled && $(<"$dir/budget") == 0 ]] || fail "time on creates the account's state with an empty budget"
grep -qx 'rate=3' "$dir/config" && grep -qx 'cap=120' "$dir/config" && grep -qx 'free=0' "$dir/config" && grep -qx 'level=grade5' "$dir/config" ||
  fail "time on writes the default configuration"
[[ $(<"$test_tmp/sudoers.d/omarchy-parent-time-kid") == 'kid ALL=(root) NOPASSWD: /usr/bin/omarchy-parent-quiz question, /usr/bin/omarchy-parent-quiz answer, /usr/bin/omarchy-parent-quiz status' ]] ||
  fail "time on grants exactly question, answer, and status" "got: $(<"$test_tmp/sudoers.d/omarchy-parent-time-kid")"
[[ -f $test_tmp/units/omarchy-parent-time.timer && -f $test_tmp/units/omarchy-parent-time.service ]] || fail "time on installs the timer units"
grep -q 'systemctl enable --now omarchy-parent-time.timer' "$CALLS" || fail "time on starts the timer" "calls: $(<"$CALLS")"
grep -q 'omarchy-apply-lock' "$CALLS" || fail "time on reapplies the lock stack for the budget gate"
[[ -f $dir/status.json ]] || fail "time on publishes status for the lock screen"
pass "time on sets up the budget, the grant, the timer, and the lock gate"

: >"$CALLS"
time_config_set kid rate 5
time_config_set kid level grade6
[[ $(grep -c '^rate=' "$dir/config") == 1 && $(grep -x 'rate=5' "$dir/config") ]] || fail "settings replace their key"
grep -qx 'level=grade6' "$dir/config" && grep -qx 'cap=120' "$dir/config" || fail "settings keep the other keys"
pass "time settings rewrite one key and keep the rest"

: >"$CALLS"
time_off kid >/dev/null
[[ ! -f $dir/enabled ]] || fail "time off drops the marker"
[[ ! -f $test_tmp/sudoers.d/omarchy-parent-time-kid ]] || fail "time off removes the grant"
[[ ! -f $test_tmp/units/omarchy-parent-time.timer ]] || fail "time off removes the timer when no account is left"
grep -q 'systemctl disable --now omarchy-parent-time.timer' "$CALLS" || fail "time off stops the timer" "calls: $(<"$CALLS")"
grep -q 'omarchy-apply-lock' "$CALLS" || fail "time off reapplies the lock stack to drop the gate"
[[ -f $dir/budget && -f $dir/config ]] || fail "time off keeps the budget and settings"
pass "time off reverses time on and keeps the history"

# A second child account keeps the timer alive while one is switched off.
time_on kid >/dev/null
time_on sib >/dev/null
: >"$CALLS"
time_off sib >/dev/null
[[ -f $test_tmp/units/omarchy-parent-time.timer ]] || fail "the timer stays while another account has screen time on"
! grep -q 'disable' "$CALLS" || fail "the timer is not stopped while another account needs it"
pass "the timer serves every child account and only goes with the last one"


# The school schedule: parsed once, stored normalized, shown back readably.
time_on kid >/dev/null
time_school kid mon-fri 08:00-15:30 sat 9:00-11:00 >/dev/null
[[ $(<"$dir/schedule") == $'12345 0800 1530\n6 0900 1100' ]] || fail "school windows are stored as day digits and HHMM" "got: $(<"$dir/schedule")"
grep -q '"school":' "$dir/status.json" || fail "setting the schedule refreshes status"
[[ $(schedule_days 'Mon,Wed,fri') == 135 ]] || fail "day lists parse case-insensitively"
[[ $(schedule_days weekends) == 67 && $(schedule_days daily) == 1234567 ]] || fail "named day sets parse"
[[ $(schedule_days sat-mon) == 167 ]] || fail "day ranges wrap past Sunday"
! schedule_days fry >/dev/null || fail "an unknown day is rejected"
! schedule_window 08:00-07:00 >/dev/null || fail "a window must end after it starts"
! schedule_window 25:00-26:00 >/dev/null || fail "an impossible time is rejected"
[[ $(time_school kid) == *"Mon Tue Wed Thu Fri 08:00-15:30"* && $(time_school kid) == *"Sat 09:00-11:00"* ]] || fail "the schedule shows readably"
time_school kid off >/dev/null
[[ ! -e $dir/schedule ]] || fail "school off clears the schedule"
[[ $(time_school kid) == "No school schedule for kid." ]] || fail "an empty schedule says so"
pass "the school schedule parses, normalizes, and clears"

# The feature reaches the parent through the dispatcher, not by editing it.
grep -q '^# omarchy:summary=Screen time earned with arithmetic' "$parent_time" || fail "omarchy-parent-time announces itself as a feature"
! grep -q '^  time)' "$parent" || fail "omarchy-parent carries no time code of its own"
[[ $(OMARCHY_PATH="$ROOT" bash "$parent" --help) == *"time      Screen time earned with arithmetic"* ]] || fail "omarchy-parent --help lists screen time as a feature"
grep -Fq 'source "$OMARCHY_PATH/install/helpers/parent.sh"' "$parent_time" || fail "omarchy-parent-time installs grants through the shared helper"
pass "screen time plugs into omarchy-parent as a feature command"
