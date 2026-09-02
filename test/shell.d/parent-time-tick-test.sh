#!/bin/bash
#
# The screen-time tick charges a minute only for an active, unlocked graphical
# session, locks every graphical session once the budget is spent, and ends
# console logins. logind, the shell's IPC, and runuser are stubbed; the budget
# itself goes through the real omarchy-parent-quiz against a scratch root.

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

tick="$ROOT/bin/omarchy-parent-time-tick"
test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
mkdir -p "$stub_bin"
export CALLS="$test_tmp/calls"

# STUB_SESSIONS: one "id:user:type:active" per line.
cat >"$stub_bin/loginctl" <<'SH'
#!/bin/bash
case $1 in
  list-sessions)
    printf '%s\n' "${STUB_SESSIONS:-}" | awk -F: 'NF { print $1, "1000", $2 }'
    ;;
  show-session)
    id=$2; prop=$4
    line=$(printf '%s\n' "${STUB_SESSIONS:-}" | awk -F: -v id="$id" '$1 == id { print; exit }')
    IFS=: read -r _ user type active <<<"$line"
    case $prop in
      Name) echo "Name=$user" ;;
      Class) echo "Class=user" ;;
      Type) echo "Type=$type" ;;
      Active) echo "Active=$active" ;;
    esac
    ;;
  terminate-session)
    printf 'terminate %s\n' "$2" >>"$CALLS"
    ;;
esac
SH

# runuser carries the shell IPC: isLocked answers from STUB_LOCKED, or true
# once a lock was requested in this run (the marker outlives the call, since
# every IPC call is its own process); a missing shell (STUB_SHELL=absent)
# fails every call.
cat >"$stub_bin/runuser" <<'SH'
#!/bin/bash
[[ ${STUB_SHELL:-present} == present ]] || exit 1
args="$*"
case $args in
  *"lock isLocked"*)
    if [[ -e $STUB_LOCK_MARKER || ${STUB_LOCKED:-false} == true ]]; then echo true; else echo false; fi
    ;;
  *"lock lock"*) printf 'lock\n' >>"$CALLS"; touch "$STUB_LOCK_MARKER" ;;
esac
SH
cat >"$stub_bin/id" <<'SH'
#!/bin/bash
echo 1000
SH
chmod +x "$stub_bin"/*

state="$test_tmp/state"
dir="$state/kid/time"
mkdir -p "$dir"
touch "$dir/enabled"
printf 'rate=3\ncap=120\n' >"$dir/config"
export OMARCHY_PARENT_STATE_DIR="$state"

export STUB_LOCK_MARKER="$test_tmp/locked"
run_tick() {
  : >"$CALLS"
  rm -f "$STUB_LOCK_MARKER"
  PATH="$stub_bin:$ROOT/bin:$PATH" bash "$tick"
}

budget() { cat "$dir/budget"; }

printf '180\n' >"$dir/budget"
printf '%s\n' "$(date +%F)" >"$dir/day"

STUB_SESSIONS="3:kid:wayland:yes" STUB_LOCKED=false run_tick
[[ $(budget) == 120 ]] || fail "an active unlocked graphical session is charged a minute" "budget: $(budget)"
[[ ! -s $CALLS ]] || fail "nothing is locked while time remains" "calls: $(<"$CALLS")"
pass "an active unlocked session is charged a minute"

STUB_SESSIONS="3:kid:wayland:yes" STUB_LOCKED=true run_tick
[[ $(budget) == 120 ]] || fail "a locked session is not charged" "budget: $(budget)"
STUB_SESSIONS="3:kid:wayland:no" STUB_LOCKED=false run_tick
[[ $(budget) == 120 ]] || fail "an inactive session is not charged" "budget: $(budget)"
STUB_SESSIONS="" run_tick
[[ $(budget) == 120 ]] || fail "no session, no charge" "budget: $(budget)"
STUB_SESSIONS="3:other:wayland:yes" STUB_LOCKED=false run_tick
[[ $(budget) == 120 ]] || fail "another account's session is not the kid's" "budget: $(budget)"
pass "locked, inactive, absent, and other users' sessions are free"

STUB_SESSIONS="3:kid:wayland:yes" STUB_LOCKED=false run_tick
STUB_SESSIONS="3:kid:wayland:yes" STUB_LOCKED=false run_tick
[[ $(budget) == 0 ]] || fail "the budget runs down to zero and stops there" "budget: $(budget)"
grep -qx lock "$CALLS" || fail "the session is locked once the budget is spent" "calls: $(<"$CALLS")"
grep -q 'locked session 3' "$dir/log" || fail "the lock is logged"
pass "the session locks the moment the budget is spent"

STUB_SESSIONS="3:kid:wayland:yes" STUB_LOCKED=true run_tick
[[ ! -s $CALLS ]] || fail "an already locked session is left alone at zero" "calls: $(<"$CALLS")"
pass "a locked session at zero budget is left alone"

STUB_SESSIONS=$'3:kid:wayland:yes\n7:kid:tty:yes' STUB_LOCKED=false run_tick
grep -qx 'terminate 7' "$CALLS" || fail "a console login is ended at zero budget" "calls: $(<"$CALLS")"
! grep -qx 'terminate 3' "$CALLS" || fail "a graphical session with a shell is locked, not ended"
pass "console logins are ended once the budget is spent"

STUB_SESSIONS="3:kid:wayland:yes" STUB_SHELL=absent run_tick
grep -qx 'terminate 3' "$CALLS" || fail "a graphical session with no shell to lock it is ended" "calls: $(<"$CALLS")"
grep -q 'no shell to lock it' "$dir/log" || fail "ending a shell-less session is logged"
pass "a session without a shell is ended rather than left unlocked"

# A tick with nobody logged in still rolls the day over.
printf '2000-01-01\n' >"$dir/day"
printf 'rate=3\ncap=120\nfree=10\n' >"$dir/config"
STUB_SESSIONS="" run_tick
[[ $(budget) == 600 ]] || fail "the free minutes arrive with the new day" "budget: $(budget)"
[[ $(<"$dir/earned") == 0 ]] || fail "the tally resets with the new day"
pass "the tick rolls the day over even with nobody logged in"

# School hours: an unlocked session is neither charged nor, at zero, locked.
printf '12345 0800 1530\n' >"$dir/schedule"
printf '120\n' >"$dir/budget"
OMARCHY_PARENT_NOW="2 1000" STUB_SESSIONS="3:kid:wayland:yes" STUB_LOCKED=false run_tick
[[ $(budget) == 120 ]] || fail "school hours are not charged" "budget: $(budget)"
printf '0\n' >"$dir/budget"
OMARCHY_PARENT_NOW="2 1000" STUB_SESSIONS=$'3:kid:wayland:yes\n7:kid:tty:yes' STUB_LOCKED=false run_tick
[[ ! -s $CALLS ]] || fail "nothing is locked or ended during school hours" "calls: $(<"$CALLS")"
OMARCHY_PARENT_NOW="2 1600" STUB_SESSIONS="3:kid:wayland:yes" STUB_LOCKED=false run_tick
grep -qx lock "$CALLS" || fail "after school the lock resumes at zero budget" "calls: $(<"$CALLS")"
rm "$dir/schedule"
pass "school hours pause the countdown and the lock"

rm "$dir/enabled"
printf '180\n' >"$dir/budget"
STUB_SESSIONS="3:kid:wayland:yes" STUB_LOCKED=false run_tick
[[ $(budget) == 180 ]] || fail "an account with screen time off is not touched" "budget: $(budget)"
pass "accounts with screen time off are skipped"

grep -q '^# omarchy:summary=' "$tick" || fail "the tick carries command metadata"
grep -q '^ExecStart=/usr/bin/omarchy-parent-time-tick$' "$ROOT/default/parent/omarchy-parent-time.service" || fail "the service unit runs the tick"
grep -q '^OnUnitActiveSec=1min$' "$ROOT/default/parent/omarchy-parent-time.timer" || fail "the timer fires every minute"
grep -q '^ConditionPathExistsGlob=/var/lib/omarchy/parent/\*/time/enabled$' "$ROOT/default/parent/omarchy-parent-time.service" || fail "the service is inert with no screen time on"
pass "the timer units run the tick once a minute while screen time is on"
