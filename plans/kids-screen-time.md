# Plan: Kids mode, phase 1 — screen time earned with math

Revision 1. Builds on phase 0 (`plans/kids-passwords.md`): the child profile, the parent password kept for root, the kid account outside `wheel`, and `omarchy-parent` as the parent's control command.

## Ask

A child install where the kid earns time on the computer by solving arithmetic at her grade level (grade 5/6). Start with the four operations; the machine must actually hold her to it, not merely suggest it.

## Shape

A **screen-time budget** per child account, owned by root. While a graphical session is unlocked the budget counts down; at zero the session locks. On the lock screen she is offered arithmetic instead of the password field; every correct answer credits minutes, root checks the answers, and once the budget is positive the normal password unlock is allowed. The parent sets the rate, the daily cap, any free minutes, and the level under `sudo omarchy-parent time`, and can grant time outright.

"Force" is delivered by root, not by the user interface: the budget and its countdown, the locking, the answer checking, and a PAM backstop on the unlock all live outside the kid's account. Her shell is only a client that shows the question and types the answer.

## What this builds on

- **Phase 0.** `omarchy-profile-child`, `omarchy-parent` with its `apply` plumbing and per-account sudoers grants (`/etc/sudoers.d/omarchy-parent-<kid>`, staged and checked by `visudo`), the parent password as root's.
- **The lock screen.** `shell/plugins/lock/` (`omarchy.lock`, a `service` plugin) locks through the compositor's session-lock protocol, authenticates with a `PamContext` against `/etc/pam.d/omarchy-lock-password`, and recovers a stranded lock if the shell dies. Its IPC target `lock` offers `lock`, `isLocked`, `status`, `preview`, `hidePreview`, and no unlock, so nothing on the kid's side can lift a lock except PAM succeeding. `bin/omarchy-apply-lock` writes the PAM stack and is what `omarchy-system-sleep-lock` and friends call.
- **PAM gates.** The fingerprint setup already inserts `pam_exec.so quiet /usr/bin/omarchy-hw-laptop-closed` into PAM stacks; the same mechanism carries a budget gate.
- **Locking from outside the session.** `bin/omarchy-shell` recovers `WAYLAND_DISPLAY` from `XDG_RUNTIME_DIR` when called from a TTY or ssh, so a root process can lock the kid's session by running it as her.
- **Conventions.** Machine state under `/var/lib/omarchy/<area>/`; `default/**` ships wholesale to `/usr/share/omarchy/default/`, so unit files there need no packaging change; system units get installed at runtime the way the provisioning units are; bar widgets follow `shell/plugins/bar/widgets/SystemUpdate.qml` (a `Process` on a `Timer`).

## Threat model, stated plainly

- Enforced by root: the budget files, the per-minute countdown, the lock at zero, the answer checking that credits time, and the PAM gate that refuses an unlock at zero budget. Killing the shell does not help: the compositor keeps the session locked and the restarted shell reclaims it (existing stranded-lock recovery). Editing state does not help: everything is root-owned. Stopping the countdown does not help: it is a root timer.
- A kid who logs in on a text console (Ctrl+Alt+F3) to work around the desktop: the tick terminates non-graphical sessions of the child account while the budget is zero, and masking `getty@tty2-6` on child installs is a one-command hardening (`omarchy-parent tty off`) worth shipping alongside.
- Not defended, by choice: a live USB (phase 0's BIOS-password advice stands), and a kid who writes a program to solve her own arithmetic, who has earned the time.
- Not a bypass to worry about: the shell's own "lock when the budget hits zero" is kid-side convenience; the root tick relocks within a minute regardless.

## Design

### 1. State: `/var/lib/omarchy/parent/<kid>/time/`

Root-owned, directory 0755, so the kid's shell can read status without privilege. Written only by the root helpers below.

- `enabled` — marker; gating is on.
- `config` — key=value: `rate` (minutes per correct answer, default 3), `cap` (minutes that can be earned per day, default 120), `free` (minutes granted at the start of each day before any question, default 0), `level` (`grade5` or `grade6`).
- `budget` — seconds remaining, integer.
- `day` — the local date the daily counters belong to; `earned` — minutes earned today.
- `question` — 0600, the pending question: id, expected answer, issued-at, attempts.
- `status.json` — 0644, rewritten by every tick and credit: `{"enabled":true,"budget":540,"earnedToday":45,"cap":120,"level":"grade5"}`. The shell reads this file and nothing else.
- `log` — one line per event (question, correct, wrong, credit, grant, lock), for `omarchy-parent time log`.

`OMARCHY_PARENT_STATE_DIR` overrides the root for tests, in the style of `OMARCHY_PROVISIONING_DIR`.

### 2. The kid-facing root helper: `bin/omarchy-parent-quiz`

Hidden, root-only, reached from the kid's shell through a NOPASSWD grant. Every subcommand has a fixed argument list so the grant can name each one exactly, and the only free-form input travels over stdin.

- `question` — generates a question for the account's level, stores it in `question` with its expected answer, prints `<id> <text>` (for example `17 What is 342 + 519?`). A new question supersedes any pending one; a pending question expires after ten minutes.
- `answer` — reads `<id> <value>` from stdin. Correct: credits `rate` minutes, bounded by today's cap, updates `budget`, `earned`, `status.json`, prints `correct <budget-seconds>`. Wrong: counts an attempt, prints `wrong` or, after the second wrong attempt, `wrong <expected>` and retires the question. Nothing else can credit time.
- `status` — prints `status.json`.
- `gate` — exit 0 when gating is off or `budget` is positive, else 1. This is the PAM backstop (§4); it runs as whichever user PAM runs as and needs no privilege, since it only reads the 0644 status.
- `--user NAME consume SECONDS` and `--user NAME credit MINUTES` — root only, for the tick and the parent's `grant`; the grant never lists these forms. `consume 0` is how the tick rolls the day over and refreshes `status.json` with nobody logged in.

Grant, written by `omarchy-parent time on` to `/etc/sudoers.d/omarchy-parent-time-<kid>` through the same stage-validate-install path as phase 0's grants:

```
<kid> ALL=(root) NOPASSWD: /usr/bin/omarchy-parent-quiz question, /usr/bin/omarchy-parent-quiz answer, /usr/bin/omarchy-parent-quiz status
```

The generator, in bash arithmetic, integers only in this phase so the answer field is a plain number:

- `grade5`: addition and subtraction of numbers up to five digits with no negative results; multiplication of a two-digit by a two-digit number and a three-digit by a one-digit number; division of a three- or four-digit number by a one-digit divisor with no remainder (built by multiplying, so it always divides exactly).
- `grade6`: everything above, plus three-digit by two-digit multiplication, exact division by a two-digit divisor, and simple order of operations (`a + b × c`, `a × b − c`).
- Operands avoid 0, 1, and powers of ten; the operation mix is weighted so a session is not all addition. Weights and ranges live in one table at the top of the script so they are easy to tune.

### 3. The countdown: `bin/omarchy-parent-time-tick` and a system timer

`default/parent/omarchy-parent-time.timer` (every minute, `AccuracySec=10s`) and `.service` (oneshot, runs the tick as root) ship in `default/parent/`; `omarchy-parent time on` installs them to `/etc/systemd/system/` and enables the timer, the way the factory reset installs the provisioning units. The tick, for every child account with `enabled`:

- Rolls the day over at local midnight: resets `earned`, adds `free` minutes to `budget` if configured.
- Reads the account's sessions from logind (`loginctl list-sessions`, then `show-session -p Type -p Class -p Active -p LockedHint`). If any graphical session is active and not locked, subtracts 60 seconds. Sleep, the idle lock, and a locked screen all stop the clock, since they show as locked or inactive.
- At zero or below: locks every graphical session by running `omarchy-shell -q lock lock` as the kid (`runuser -u <kid> -- env XDG_RUNTIME_DIR=/run/user/<uid> OMARCHY_PATH=/usr/share/omarchy omarchy-shell -q lock lock`), and terminates the account's non-graphical sessions (`loginctl terminate-session`), logging each. The lock state itself is asked of the shell over the same IPC (`lock isLocked`), since the shell's session lock does not raise logind's `LockedHint`; a session whose shell does not answer counts as unlocked, and, if it cannot be locked, is ended.
- Rewrites `status.json` every tick so the shell's remaining-time display stays honest.

### 4. The PAM backstop

`bin/omarchy-apply-lock` writes `auth requisite pam_exec.so quiet /usr/bin/omarchy-parent-quiz gate` as the first line of both `/etc/pam.d/omarchy-lock-password` and `/etc/pam.d/omarchy-lock-fingerprint` when the profile is child and the account's `enabled` marker exists, so neither a password nor a print opens a locked-out session; `requisite` fails the unlock immediately without prompting for the password. `omarchy-parent time on` and `off` rerun `omarchy-apply-lock` so the line follows the setting, and its reruns (fingerprint setup, sleep lock) keep it because the decision is made inside the writer, not patched in afterwards. A shell that somehow offered the password field at zero budget would still be refused here.

### 5. The lock screen math gate (`shell/plugins/lock/`)

- `Service.qml` watches `status.json` with a `FileView` (`watchChanges`), like it already watches the PAM file. It exposes `timeGated` (child profile, gating on, budget zero) and the remaining minutes.
- While locked and `timeGated`, `LockView.qml` shows the question where the password field is ("What is 342 + 519?") with a numeric input and a one-line result ("+3 minutes, 12 banked" or "Not quite, try again"). The view asks the service for a question on lock and after each answer; the service runs `sudo -n /usr/bin/omarchy-parent-quiz question` and feeds `answer` over stdin through `Process`, the way the plugin already shells out for fingerprint and lid state. Once the budget is positive the password field returns and the normal PAM unlock proceeds.
- While unlocked, the service locks itself the moment `status.json` reports zero (immediate feedback; root relocks within a minute anyway), and sends toasts at five and one minutes left through `omarchy-notification-send`.
- The pure parts (question parsing, answer normalization, the gate state machine, the banked-time wording) live in `shell/plugins/lock/MathGateModel.js` with the CommonJS guard the other models use, so Node can test them.
- Visual verification per `agents/skills/visual-verification.md`: lock at zero budget, a wrong answer, a correct answer crediting time, the password field returning.

### 6. The parent's controls: `sudo omarchy-parent time`

New subcommand group on phase 0's `omarchy-parent` (root, child installs only):

- `status` — budget, earned today, cap, level, whether gating is on.
- `on` / `off` — create or remove the state directory's `enabled` marker, install or remove the sudoers grant and the timer, rerun `omarchy-apply-lock`. `off` leaves the budget history in place.
- `rate MIN`, `cap MIN`, `free MIN`, `level grade5|grade6` — write `config`.
- `grant MIN` — credits time outright (a reward, or a homework night), logged as such.
- `log` — the event log.
- `tty off|on` — mask or unmask `getty@tty2` through `tty6` on this machine. `omarchy-parent apply` closes them on every child install (decision 4), so this is the way back.

Later phases can add a menu entry (_Setup > Parental > Screen Time_), a bedtime schedule, and subjects beyond arithmetic; none of that changes the state or the helpers above.

### 7. Optional in this phase: a remaining-time bar widget

`shell/plugins/bar/widgets/ScreenTime.qml` with its manifest, polling `status.json` on a timer and showing minutes left with a warning color under five. Cheap, since the file is world-readable, and `omarchy-parent time on` can enable it for the kid's bar through the shell's plugin IPC; worth doing only after the gate itself works.

### 8. Tests

- `test/shell.d/parent-quiz-test.sh`: with `OMARCHY_PARENT_STATE_DIR` pointing at a scratch tree and running as namespaced root where `unshare` allows (the `dns-sudoers-test.sh` pattern), the generator produces only exact-division and non-negative problems within each level's ranges over a few hundred draws; `answer` credits exactly `rate` minutes on a correct answer, never past the cap, and nothing on a wrong one; the second wrong attempt reveals the expected answer; a stale or superseded question earns nothing; `gate` follows the budget; the sudoers grant lists exactly the three subcommands and parses with `visudo`.
- `test/shell.d/parent-time-tick-test.sh`: stubbed `loginctl` and `runuser`; the budget decrements only for an active unlocked graphical session; it holds while locked or asleep; zero locks every graphical session and terminates console sessions; midnight resets `earned` and adds `free`.
- `test/shell.d/lock-*`: the existing lock tests extend with the PAM gate line placement (`omarchy-apply-lock` output with and without the marker), and a Node test for `MathGateModel.js`.
- Acceptance (`test/acceptance.d/`, child VM): with gating on and the budget zeroed, `omarchy-parent-quiz gate` exits 1, the lock shows a question, a correct answer typed through the harness credits time, and the password unlock then succeeds.

### 9. Docs

`manual/48-security.md`'s "Child installs" section gains a "Screen time" subsection: how earning works, the defaults, the parent commands, and the honest limits. The agent skill's privilege note needs nothing new.

## Sequencing

1. State layout, the generator, and `omarchy-parent-quiz` with its tests.
2. The tick, the timer units under `default/parent/`, and the lock-as-the-kid path, with tests.
3. The PAM gate in `omarchy-apply-lock`, with tests.
4. `omarchy-parent time` and `tty`, the sudoers grant, and the manual.
5. The lock screen gate, its model and tests, and visual verification.
6. The bar widget, if wanted.

## Decisions

Confirmed by Peter on 2026-09-01:

1. **Defaults.** Three minutes per correct answer, a 120-minute daily cap, no free minutes, `grade5`.
2. **Revealing answers.** After the second wrong attempt, show the answer and move on with no credit.
3. **Quiz versus password.** The question appears only when the budget is empty; a positive budget unlocks with the password as usual.
4. **Console hardening.** Child installs mask the text consoles by default; `omarchy-parent tty on` reopens them.
5. **What counts.** Any unlocked graphical session burns time. Exempting particular apps is a later phase.
