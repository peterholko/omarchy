#!/bin/bash
#
# Math time is the arithmetic app of a child install: practice at any grade,
# checked in the app, or a set that earns screen time through
# omarchy-parent-quiz. The model is pure JavaScript shared with QML, so Node
# exercises it; the wiring is asserted from the QML source.

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const quiz = requireFromRoot('shell/plugins/math/MathModel.js')
const status = quiz.gateFromStatus('{"enabled":true,"school":false,"budget":0,"earnedToday":12,"usedToday":300,"cap":120,"rate":6,"questions":5,"sessionMinutes":30,"level":"grade5"}', true)
assert(status.gated, 'an empty budget on a child install is gated')
assertEqual(status.questions, 5, 'the session length comes from status.json')
assertEqual(status.sessionMinutes, 30, 'the session earnings come from status.json')
assertEqual(status.level, 'grade5', 'the parent\'s level comes along')
assertEqual(quiz.gateFromStatus('{"enabled":true,"budget":0,"level":"grade2"}', true).level, 'grade2', 'a lower level comes along')
assertEqual(quiz.gateFromStatus('{"enabled":true,"budget":0,"level":"grade9"}', true).level, 'grade5', 'an unknown level falls back to grade 5')
assertEqual(quiz.gateFromStatus('{"enabled":true,"budget":0,"rate":4,"questions":3}', true).sessionMinutes, 12, 'session minutes fall back to rate times questions')
assert(!quiz.gateFromStatus('{"enabled":true,"school":true,"budget":0}', true).gated, 'school hours are not gated')
assert(!quiz.gateFromStatus('{"enabled":true,"budget":0}', false).gated, 'a default install is never gated')
assert(!quiz.gateFromStatus('not json', true).gated, 'unreadable status fails open')
assertDeepEqual(quiz.GRADES, [1, 2, 3, 4, 5, 6], 'six grades')
assertEqual(quiz.PRACTICE_COUNT, 10, 'a practice set is ten questions')
assertEqual(quiz.levelNumber('grade3'), 3, 'a level name becomes its number')
assertEqual(quiz.levelNumber('nonsense'), 5, 'an unknown level is grade 5')
assertEqual(quiz.levelName(2), 'grade2', 'a number becomes its level name')
assertEqual(quiz.levelName(0), 'grade5', 'an out-of-range number is grade 5')
assertEqual(quiz.gradeLabel(4), 'Grade 4', 'the picker labels a grade')
assert(quiz.gradeBlurb(1).indexOf('20') !== -1 && quiz.gradeBlurb(6).indexOf('order of operations') !== -1, 'each grade says what it asks')
assertDeepEqual(quiz.parseQuestion('17 What is 342 + 519?'), { id: '17', text: 'What is 342 + 519?' }, 'an earning question splits into id and text')
assertDeepEqual(quiz.parsePractice('What is 7 × 8?\t56\n'), { text: 'What is 7 × 8?', answer: '56' }, 'a practice line splits into text and answer')
assertEqual(quiz.parsePractice('What is 7 × 8?'), null, 'a practice line without an answer is refused')
assertEqual(quiz.parsePractice('What is 7 × 8?\tfifty-six'), null, 'a practice answer must be a number')
assertEqual(quiz.normalizeAnswer(' 1,234 '), '1234', 'answers drop commas and spaces')
assertDeepEqual(quiz.judgePractice('56', '56', 0), { kind: 'correct', credited: 0, budget: 0 }, 'a right practice answer is correct and earns nothing')
assertDeepEqual(quiz.judgePractice('55', '56', 0), { kind: 'wrong', expected: '' }, 'a first practice miss keeps the question')
assertDeepEqual(quiz.judgePractice('55', '56', 1), { kind: 'wrong', expected: '56' }, 'a second practice miss reveals the answer')
assertDeepEqual(quiz.judgePractice('', '56', 0), { kind: 'wrong', expected: '' }, 'an empty answer is a miss')
assert(quiz.isCalculatorAppId('omacalc'), 'the Omacalc Wayland app id is recognized')
assert(!quiz.isCalculatorAppId('libreoffice-calc'), 'a spreadsheet is not mistaken for Omacalc')
assertDeepEqual(quiz.parseAnswer('correct 6 360'), { kind: 'correct', credited: 6, budget: 360 }, 'a correct earning answer carries its credit and the budget')
assertDeepEqual(quiz.parseAnswer('wrong 861'), { kind: 'wrong', expected: '861' }, 'a second wrong answer reveals the expected value')
assertEqual(quiz.feedbackFor({ kind: 'correct', credited: 6, budget: 360 }, 'earn'), 'Correct! +6 min', 'an earning credit says what was earned')
assertEqual(quiz.feedbackFor({ kind: 'correct', credited: 0, budget: 360 }, 'earn'), "Correct! You have reached today's limit, so no more minutes.", 'a capped credit says so')
assertEqual(quiz.feedbackFor({ kind: 'correct', credited: 0, budget: 0 }, 'practice'), 'Correct!', 'a practice hit is just right')
assertEqual(quiz.feedbackFor({ kind: 'wrong', expected: '' }, 'practice'), 'Not quite. Try once more.', 'a first miss invites another try')
assertEqual(quiz.feedbackFor({ kind: 'wrong', expected: '861' }, 'earn'), 'The answer is 861.', 'a second miss shows the answer')
assertEqual(quiz.feedbackFor({ kind: 'stale' }, 'earn'), 'That one timed out. Here is a fresh one.', 'a stale question is replaced')
assert(quiz.questionDone({ kind: 'correct', credited: 6, budget: 360 }), 'a right answer finishes the question')
assert(quiz.questionDone({ kind: 'wrong', expected: '861' }), 'a second miss finishes the question')
assert(!quiz.questionDone({ kind: 'wrong', expected: '' }), 'a first miss keeps the question')
assert(!quiz.questionDone({ kind: 'stale' }), 'a stale question is replaced, not counted')
assertEqual(quiz.progressLabel(0, 5), 'Question 1 of 5', 'progress counts from one')
assertEqual(quiz.progressLabel(4, 5), 'Question 5 of 5', 'progress reaches the last question')
assertEqual(quiz.streakLabel(1), '', 'one right is not a run')
assertEqual(quiz.streakLabel(3), '3 in a row', 'three right is a run')
assertEqual(quiz.formatDuration(45), '45 s', 'short durations are seconds')
assertEqual(quiz.formatDuration(130), '2 min 10 s', 'longer durations are minutes and seconds')
assertEqual(quiz.remainingLabel(0), 'No time left', 'an empty budget says so')
assertEqual(quiz.remainingLabel(90), '2 min left', 'a budget rounds up to minutes')
assertDeepEqual(quiz.sessionSummary('practice', 8, 10, 130, 0, 0, 4), ['8 of 10 right in 2 min 10 s', 'Best run: 4 in a row'], 'a practice summary is the score and the run')
assertDeepEqual(quiz.sessionSummary('earn', 5, 5, 200, 30, 1800, 5), ['5 of 5 right in 3 min 20 s', 'Best run: 5 in a row', '+30 min earned', '30 min banked'], 'an earning summary adds the minutes')
assertDeepEqual(quiz.sessionSummary('earn', 1, 5, 60, 0, 0, 1), ['1 of 5 right in 1 min 0 s', 'No minutes this time', '0 min banked'], 'a poor set says no minutes, and no run')
JS
pass "the math model judges practice locally and shapes the earning conversation"

qml="$ROOT/shell/plugins/math/Math.qml"
grep -q 'WlrLayershell.namespace: "omarchy-math"' "$qml" || fail "the app keeps the layer namespace root's guard looks for"
grep -q 'WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive' "$qml" && grep -q 'WlrLayershell.layer: WlrLayer.Overlay' "$qml" || fail "the app holds the keyboard on the overlay layer"
grep -q 'IdleInhibitor {' "$qml" && grep -q 'enabled: root.opened' "$qml" || fail "the screen stays on while the app is open"
grep -q '\["sudo", "-n", "/usr/bin/omarchy-parent-quiz", "question"\]' "$qml" || fail "an earning question comes from root through the grant"
grep -q 'sudo -n /usr/bin/omarchy-parent-quiz answer' "$qml" || fail "an earning answer goes to root through the grant"
grep -q '\["/usr/bin/omarchy-parent-quiz", "practice", Quiz.levelName(grade)\]' "$qml" || fail "a practice question comes from the generator without privilege"
grep -q 'Quiz.judgePractice(answer, expectedAnswer, attempts)' "$qml" || fail "a practice answer is judged in the app"
grep -q 'if (status.gated) {' "$qml" && grep -q 'mode = "earn"' "$qml" || fail "with no time left the app opens straight into an earning set"
grep -q 'readonly property int level: earning ? Quiz.levelNumber(status.level) : grade' "$qml" || fail "earning is at the parent's level, practice at the kid's pick"
grep -q 'visible: root.canEarn' "$qml" || fail "the earn choice is only offered while screen time is on"
grep -q 'math-grade' "$qml" || fail "the grade she picked is remembered"
for screen in start question results; do
  grep -q "visible: root.screen === \"$screen\"" "$qml" || fail "the app has a $screen screen"
done
grep -q 'objectName: "feedback"' "$qml" && grep -q 'feedbackKind === "correct" ? Color.accent' "$qml" || fail "the verdict banner colours right and wrong apart"
grep -q 'Quiz.isCalculatorAppId(toplevel.appId)) toplevel.close()' "$qml" || fail "Omacalc is closed while the app is up"
grep -q '"when":"omarchy-profile-child","action":"omarchy-shell shell summon omarchy.math' "$ROOT/default/omarchy/omarchy-menu.jsonc" || fail "the menu offers Math time on every child install, screen time on or off"
grep -q '^Exec=omarchy-shell shell summon omarchy.math$' "$ROOT/applications/child/Math Time.desktop" || fail "the child launcher has a Math Time entry"
pass "Math time is wired as the child install's math app"
