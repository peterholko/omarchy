#!/bin/bash
#
# On a child install with screen time on, the lock screen's PAM stack refuses
# the unlock before the password is asked while the budget is empty. The gate
# is decided inside omarchy-apply-lock, so every rerun keeps it in step.

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

apply_lock="$ROOT/bin/omarchy-apply-lock"
test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
pam_dir="$test_tmp/pam.d"
mkdir -p "$stub_bin" "$pam_dir"

# sudo runs its command with /etc/pam.d redirected into the scratch tree.
cat >"$stub_bin/sudo" <<SH
#!/bin/bash
args=()
for arg in "\$@"; do args+=("\${arg//\/etc\/pam.d/$pam_dir}"); done
exec "\${args[@]}"
SH
# A reader with a print enrolled when STUB_FINGERPRINT=yes, so the fingerprint
# stack gets written and can be checked for the gate too.
cat >"$stub_bin/omarchy-cmd-present" <<'SH'
#!/bin/bash
[[ ${STUB_FINGERPRINT:-no} == yes ]]
SH
cat >"$stub_bin/fprintd-list" <<'SH'
#!/bin/bash
echo "right-index-finger"
SH
cat >"$stub_bin/omarchy-shell" <<'SH'
#!/bin/bash
exit 1
SH
cat >"$stub_bin/omarchy-profile-child" <<'SH'
#!/bin/bash
[[ ${STUB_PROFILE:-default} == child ]]
SH
chmod +x "$stub_bin"/*

state="$test_tmp/state"
mkdir -p "$state/kid/time"
export OMARCHY_PARENT_STATE_DIR="$state"

run_apply_lock() {
  OMARCHY_INSTALL_USER=kid PATH="$stub_bin:$PATH" bash "$apply_lock" >/dev/null
}

gate='auth       requisite                   pam_exec.so quiet /usr/bin/omarchy-parent-quiz gate'

STUB_PROFILE=default run_apply_lock
! grep -qF "$gate" "$pam_dir/omarchy-lock-password" || fail "a default install has no budget gate"
[[ $(sed -n '2p' "$pam_dir/omarchy-lock-password") == 'auth       required                    pam_faillock.so preauth silent deny=10 unlock_time=120' ]] ||
  fail "the stack is unchanged without a gate" "$(head -3 "$pam_dir/omarchy-lock-password")"
pass "a default install's lock stack has no budget gate"

STUB_PROFILE=child run_apply_lock
! grep -qF "$gate" "$pam_dir/omarchy-lock-password" || fail "a child install with screen time off has no budget gate"
pass "a child install with screen time off has no budget gate"

touch "$state/kid/time/enabled"
STUB_PROFILE=child run_apply_lock
[[ $(sed -n '2p' "$pam_dir/omarchy-lock-password") == "$gate" ]] ||
  fail "the budget gate is the first auth line" "$(head -3 "$pam_dir/omarchy-lock-password")"
[[ $(grep -cF "$gate" "$pam_dir/omarchy-lock-password") == 1 ]] || fail "the gate appears once"
grep -q '^auth       required                    pam_faillock.so preauth' "$pam_dir/omarchy-lock-password" || fail "the rest of the stack follows the gate"
pass "a child install with screen time on gates the unlock on the budget"

STUB_PROFILE=child run_apply_lock
[[ $(grep -cF "$gate" "$pam_dir/omarchy-lock-password") == 1 ]] || fail "reruns do not stack gates"
rm "$state/kid/time/enabled"
STUB_PROFILE=child run_apply_lock
! grep -qF "$gate" "$pam_dir/omarchy-lock-password" || fail "turning screen time off removes the gate on the next apply"
pass "the gate follows the screen-time setting across reruns"

# The fingerprint stack carries the same gate: a print must not open a locked-out session.
touch "$state/kid/time/enabled"
STUB_PROFILE=child STUB_FINGERPRINT=yes run_apply_lock
[[ $(sed -n '2p' "$pam_dir/omarchy-lock-fingerprint") == "$gate" ]] ||
  fail "the fingerprint stack is gated on the budget too" "$(cat "$pam_dir/omarchy-lock-fingerprint")"
grep -q '^auth       required                    pam_fprintd.so' "$pam_dir/omarchy-lock-fingerprint" || fail "the fingerprint module still follows"
rm "$state/kid/time/enabled"
STUB_PROFILE=child STUB_FINGERPRINT=yes run_apply_lock
! grep -qF "$gate" "$pam_dir/omarchy-lock-fingerprint" || fail "the fingerprint gate follows the setting"
pass "the fingerprint unlock is gated on the budget as well"
