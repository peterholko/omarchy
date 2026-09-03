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

`bin/omarchy-apply-lock` writes no budget gate (Rev 2): with the budget empty the password opens the lock screen and the guard below holds the session inside _Math time_ instead. The `gate` subcommand of `omarchy-parent-quiz` stays for the tests and for a PAM stack that wants it.

### 5. Math time, the session plugin (`shell/plugins/math/`), and the guard

- `omarchy.math` is a first-party `overlay` plugin, kept loaded: a full-screen `PanelWindow` on the `Overlay` layer with exclusive keyboard focus and the namespace `omarchy-math`, an `IdleInhibitor` bound to it so the display never blanks mid-problem, and the same `sudo -n /usr/bin/omarchy-parent-quiz question` and stdin-fed `answer` calls the lock screen used to make, through the kid's passwordless grant. While the plugin is open it watches the compositor's top-level windows and closes Omacalc, including an instance already open when the session starts; the calculator remains available outside _Math time_. A session is `status.json`'s `questions` questions; the screen shows the promise ("5 questions earn 30 minutes"), the progress, the question, a digits-only field with the verdict as its placeholder, the banked time, and the elapsed time. A right answer or a second miss finishes a question, a stale one is replaced uncounted, and after the last question a results screen sums the session ("You got 4 of 5 right in 3 min 12 s. +24 min. 36 min banked."); Enter leaves, or starts another session when there is still no time. Escape leaves at any point, and the guard answers for that.
- The lock screen (`shell/plugins/lock/`) is a plain lock screen again: it shows what is banked, or "No time left: unlock to do your math", and after an unlock with an empty budget it summons the plugin through `omarchy-shell shell summon omarchy.math`. The menu offers _Math time_ on a child install with screen time on, so she can earn ahead.
- The guard is `omarchy-parent-time-tick guard`, a loop in a `Restart=always` unit that `omarchy-parent time on` installs beside the timer: every five seconds, for every account at zero budget outside school hours with an active, unlocked graphical session, it asks her Hyprland (`hyprctl -j layers`, as her, through her own runtime directory) whether the `omarchy-math` layer is up, counts a miss otherwise, and on the second miss in a row locks the session the way the tick does and logs why. A positive budget or school hours clear the count.
- The pure parts (status parsing, question and answer parsing, the session's progress and results wording) live in `shell/plugins/math/MathModel.js` with the CommonJS guard the other models use; the lock screen imports the same file for its label.

### 6. The parent's controls: `sudo omarchy-parent time`

A feature command, `bin/omarchy-parent-time`, that phase 0's `omarchy-parent` dispatches to as `omarchy-parent time ...` (root, child installs only). It shares `install_sudoers` through `install/helpers/parent.sh` and never edits `omarchy-parent`, so it can land as its own PR:

- `status` — budget, earned today, cap, level, whether gating is on.
- `on` / `off` — create or remove the state directory's `enabled` marker, install or remove the sudoers grant and the timer, rerun `omarchy-apply-lock`. `off` leaves the budget history in place.
- `rate MIN`, `cap MIN`, `free MIN`, `level grade5|grade6` — write `config`.
- `grant MIN` — credits time outright (a reward, or a homework night), logged as such.
- `log` — the event log.
- `tty off|on` — mask or unmask `getty@tty2` through `tty6` on this machine. `omarchy-parent apply` closes them on every child install (decision 4), so this is the way back.
- `school DAYS HH:MM-HH:MM ...` / `school off` / `school` — the school schedule (added on Peter's request after phase 1 landed). Windows are stored normalized in `schedule` (day digits, HHMM start and end, one per line); inside one, `omarchy-parent-quiz` reports `school` true in `status.json`, `consume` charges nothing, `gate` stands aside, and the tick neither charges nor locks, so the lock screen shows the password and the laptop is hers for schoolwork. Days accept `mon-fri`, `mon,wed,fri`, `weekdays`, `weekends`, `daily`; windows are same-day.

Later phases can add a menu entry (_Setup > Parental > Screen Time_), a bedtime schedule, and subjects beyond arithmetic; none of that changes the state or the helpers above.

### 7. Optional in this phase: a remaining-time bar widget

`shell/plugins/bar/widgets/ScreenTime.qml` with its manifest, polling `status.json` on a timer and showing minutes left with a warning color under five. Cheap, since the file is world-readable, and `omarchy-parent time on` can enable it for the kid's bar through the shell's plugin IPC; worth doing only after the gate itself works.

### 8. Tests

- `test/shell.d/parent-quiz-test.sh`: with `OMARCHY_PARENT_STATE_DIR` pointing at a scratch tree and running as namespaced root where `unshare` allows (the `dns-sudoers-test.sh` pattern), the generator produces only exact-division and non-negative problems within each level's ranges over a few hundred draws; `answer` credits exactly `rate` minutes on a correct answer, never past the cap, and nothing on a wrong one; the second wrong attempt reveals the expected answer; a stale or superseded question earns nothing; `gate` follows the budget; the sudoers grant lists exactly the three subcommands and parses with `visudo`.
- `test/shell.d/parent-time-tick-test.sh`: stubbed `loginctl` and `runuser`; the budget decrements only for an active unlocked graphical session; it holds while locked or asleep; zero locks every graphical session and terminates console sessions; midnight resets `earned` and adds `free`.
- `test/shell.d/lock-budget-gate-test.sh` asserts the lock stacks carry no gate whatever the setting; `test/shell.d/math-plugin-test.sh` covers `MathModel.js` under Node and the plugin, lock, and menu wiring from source; the tick test drives the guard with a stubbed `hyprctl`; the quiz test covers the session shape, the use counter, and the report.
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

Confirmed by Peter on 2026-09-01, and revised on 2026-09-02 after the first laptop trial:

1. **Defaults.** A session is five questions at six minutes each, so thirty minutes when every answer is right; a 120-minute daily cap, no free minutes, `grade5`. (Rev 1 had three minutes per answer, one at a time.)
2. **Revealing answers.** After the second wrong attempt, show the answer and move on with no credit.
3. **The math is a session in the desktop, not a gate on the lock screen.** Rev 1 put the question on the lock screen in place of the password field, so the kid answered and then typed her password too, and the screen blanked while she worked on paper. Now: time runs out, root locks, she unlocks with her password, and _Math time_, a full-screen plugin holding the keyboard, takes the session until the batch is done; it also opens from the menu to earn ahead. Peter's reasons: one password, and a real app that can show progress, results, and timing, and grow.
4. **Root keeps its hold with a guard, not a PAM gate.** While the budget is empty, a root loop asks her Hyprland every few seconds whether the `omarchy-math` layer is up and locks the session again otherwise, with two misses in a row so a fresh unlock has a moment. The trade, accepted: a few seconds of desktop after killing the shell, and a check that trusts her compositor's answer. The countdown and the crediting stay root's, unchanged.
5. **The screen stays on** while _Math time_ is open, through an idle inhibitor; a question stays answerable for half an hour.
6. **A report to root's disk, no email.** Each finished day is filed under `reports/<date>.txt` with use, earnings, and every question with its answer, what was given, and how long it took; `omarchy-parent time report [DATE]` prints one.
7. **Console hardening.** Child installs mask the text consoles by default; `omarchy-parent tty on` reopens them.
8. **What counts.** Any unlocked graphical session burns time. Exempting particular apps is a later phase.

## Rev 3, 2026-09-03: Math time as an app

Peter's laptop trial of Rev 2 found the math session not working at all, and he asked for a proper Math application: arithmetic for grades 1 to 6, designed with a good UX for the question and the feedback, tied into screen time so that a set the kid opens herself can add to her time. Decided:

- **One app, two modes.** _Math time_ (`shell/plugins/math`, still `omarchy.math`) opens on a start screen: a grade picker from 1 to 6, remembered in `~/.local/state/omarchy/math-grade`, and a choice between _Practice_ (ten questions, always) and _Earn time_ (the parent's `questions` at the parent's `level`, offered only while screen time is on and outside school hours). With no time left it opens straight into an earning set, as before, and root's guard and the lock screen are unchanged.
- **Practice needs no root.** `omarchy-parent-quiz practice gradeN` prints the question and its answer, tab apart, with nothing recorded and no privilege, and the app judges the answer itself, the way root judges an earning one: a second try, then the answer. Earning keeps the `question`/`answer` protocol through the sudo grant, so minutes are only ever credited for a question root generated and checked, at the grade the parent set, whatever grade she practises at.
- **Grades 1 to 6 in the generator.** Grade 1 adds and takes away within 20; grade 2 within 100 with tables of 2 to 5; grade 3 the tables to 9 × 9, their divisions, and sums to a thousand; grade 4 sums to ten thousand, hundreds times ones, and long division by one digit; grades 5 and 6 as before. `omarchy-parent time level` takes any of them.
- **The feedback is the point.** A big question, a big answer field, and a banner under it: accent-coloured "Correct!", red "Not quite. Try once more." on a first miss, red "The answer is 861." on the second, then the next question after a beat. A progress bar, "Question 3 of 10", and "4 in a row" along the top. Peter asked (2026-09-03) that a question say only Correct and the screen time gained be told at the end, so no minutes show during a set, not even the balance; the results screen carries the score, the time, the best run, and, when earning, "+30 min of screen time earned" and what is banked; _Again_ and _Done_, with only _Again_ while there is still no time.
- **In the launcher.** `applications/child/Math Time.desktop` summons it, and the menu row no longer needs screen time to be on.
- **Still to verify on the laptop**: the QML has not run under a live shell here. The laptop is where the start screen, the field, and the banner get their first look, and where the earning set is proven against the guard.

