#!/bin/bash
#
# Math time is the session where screen time is earned: a full-screen plugin
# that asks omarchy-parent-quiz's questions after the lock screen has let the
# kid in with her password. The model is pure JavaScript shared with QML, so
# Node exercises it; the wiring is asserted from the QML source.

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const quiz = requireFromRoot('shell/plugins/math/MathModel.js')
const status = quiz.gateFromStatus('{"enabled":true,"school":false,"budget":0,"earnedToday":12,"usedToday":300,"cap":120,"rate":6,"questions":5,"sessionMinutes":30,"level":"grade5"}', true)
assert(status.gated, 'an empty budget on a child install is gated')
assertEqual(status.questions, 5, 'the session length comes from status.json')
assertEqual(status.sessionMinutes, 30, 'the session earnings come from status.json')
assertEqual(status.rate, 6, 'the rate comes along')
assertEqual(status.usedToday, 300, 'the day\'s use comes along')
assertEqual(quiz.gateFromStatus('{"enabled":true,"budget":0,"rate":4,"questions":3}', true).sessionMinutes, 12, 'session minutes fall back to rate times questions')
assertEqual(quiz.gateFromStatus('{"enabled":true,"budget":0}', true).questions, 5, 'the session length defaults to five')
assert(!quiz.gateFromStatus('{"enabled":true,"school":true,"budget":0}', true).gated, 'school hours are not gated')
assert(!quiz.gateFromStatus('{"enabled":true,"budget":0}', false).gated, 'a default install is never gated')
assert(!quiz.gateFromStatus('not json', true).gated, 'unreadable status fails open')
assertDeepEqual(quiz.parseQuestion('17 What is 342 + 519?'), { id: '17', text: 'What is 342 + 519?' }, 'a question line splits into id and text')
assertEqual(quiz.normalizeAnswer(' 1,234 '), '1234', 'answers drop commas and spaces')
assert(quiz.isCalculatorAppId('omacalc'), 'the Omacalc Wayland app id is recognized')
assert(quiz.isCalculatorAppId('OMACALC.desktop'), 'the desktop-id spelling is recognized without regard to case')
assert(!quiz.isCalculatorAppId('org.gnome.Calculator'), 'an unrelated calculator is not mistaken for Omacalc')
assert(!quiz.isCalculatorAppId('libreoffice-calc'), 'a spreadsheet is not mistaken for Omacalc')
assertDeepEqual(quiz.parseAnswer('correct 6 360'), { kind: 'correct', credited: 6, budget: 360 }, 'a correct answer carries its credit and the budget')
assertDeepEqual(quiz.parseAnswer('wrong 861'), { kind: 'wrong', expected: '861' }, 'a second wrong answer reveals the expected value')
assertEqual(quiz.feedback({ kind: 'correct', credited: 6, budget: 360 }), '+6 min. 6 min banked.', 'a credit says what was earned and what is banked')
assert(quiz.questionDone({ kind: 'correct', credited: 6, budget: 360 }), 'a right answer finishes the question')
assert(quiz.questionDone({ kind: 'wrong', expected: '861' }), 'a second miss finishes the question')
assert(!quiz.questionDone({ kind: 'wrong', expected: '' }), 'a first miss keeps the question')
assert(!quiz.questionDone({ kind: 'stale' }), 'a stale question is replaced, not counted')
assertEqual(quiz.progressLabel(0, 5), 'Question 1 of 5', 'progress counts from one')
assertEqual(quiz.progressLabel(4, 5), 'Question 5 of 5', 'progress reaches the last question')
assertEqual(quiz.formatDuration(45), '45 s', 'short durations are seconds')
assertEqual(quiz.formatDuration(192), '3 min 12 s', 'longer durations are minutes and seconds')
assertEqual(quiz.resultsSummary(4, 5, 192, 24, 2160), 'You got 4 of 5 right in 3 min 12 s. +24 min. 36 min banked.', 'the results screen sums the session')
assertEqual(quiz.resultsSummary(0, 5, 30, 0, 0), 'You got 0 of 5 right in 30 s. No minutes this time. 0 min banked.', 'a session with nothing earned says so')
assertEqual(quiz.remainingLabel(0), 'No time left', 'an empty budget says so')
JS

# The plugin and the lock screen, asserted from source.
run_node_test <<'JS'
const fs = require('fs')
const manifest = JSON.parse(fs.readFileSync(path.join(root, 'shell/plugins/math/manifest.json'), 'utf8'))
const plugin = fs.readFileSync(path.join(root, 'shell/plugins/math/Math.qml'), 'utf8')
const service = fs.readFileSync(path.join(root, 'shell/plugins/lock/Service.qml'), 'utf8')
const view = fs.readFileSync(path.join(root, 'shell/plugins/lock/LockView.qml'), 'utf8')
const menu = fs.readFileSync(path.join(root, 'default/omarchy/omarchy-menu.jsonc'), 'utf8')
assertEqual(manifest.id, 'omarchy.math', 'the plugin is omarchy.math')
assertDeepEqual(manifest.kinds, ['overlay'], 'the plugin is an overlay')
assertEqual(manifest.entryPoints.overlay, 'Math.qml', 'the overlay entry point is Math.qml')
assert(manifest.keepLoaded === true, 'the plugin stays loaded so the lock screen can summon it at once')
assert(/WlrLayershell\.namespace: "omarchy-math"/.test(plugin), 'the overlay is the omarchy-math layer the guard looks for')
assert(/WlrLayershell\.layer: WlrLayer\.Overlay/.test(plugin), 'the overlay sits above everything')
assert(/WlrLayershell\.keyboardFocus: WlrKeyboardFocus\.Exclusive/.test(plugin), 'the overlay holds the keyboard')
assert(/anchors \{ top: true; bottom: true; left: true; right: true \}/.test(plugin), 'the overlay is full screen')
assert(/IdleInhibitor \{\s*window: panel\s*enabled: root\.opened\s*\}/.test(plugin), 'the screen stays on while the session is open')
assert(/command: \["sudo", "-n", "\/usr\/bin\/omarchy-parent-quiz", "question"\]/.test(plugin), 'questions come through the sudo grant with the exact argument list')
assert(/Util\.shellQuote\(questionId\) \+ " " \+ Util\.shellQuote\(answer\) \+ " \| sudo -n \/usr\/bin\/omarchy-parent-quiz answer"/.test(plugin), 'answers travel over stdin to the granted answer form, quoted')
assert(/function open\(payloadJson\)[\s\S]*?startSession\(\)/.test(plugin), 'opening starts a session')
const openMath = plugin.match(/function open\(payloadJson\) \{[\s\S]*?\n  \}/)[0]
assert(openMath.indexOf('opened = true') < openMath.indexOf('blockCalculatorWindows()'), 'calculator blocking starts as soon as Math time opens')
assert(openMath.indexOf('blockCalculatorWindows()') < openMath.indexOf('startSession()'), 'the calculator is closed before the first question is requested')
assert(/function blockCalculatorWindows\(\) \{\s*if \(!opened\) return[\s\S]*?ToplevelManager\.toplevels\.values[\s\S]*?Quiz\.isCalculatorAppId\(toplevel\.appId\)[\s\S]*?toplevel\.close\(\)/.test(plugin), 'open Omacalc windows are closed only during Math time')
assert(/Connections \{\s*target: ToplevelManager\.toplevels\s*function onValuesChanged\(\) \{ root\.blockCalculatorWindows\(\) \}\s*\}/.test(plugin), 'new Omacalc windows are closed throughout Math time')
assert(/if \(answered >= total\) \{\s*finished = true/.test(plugin), 'the session ends after its questions')
assert(/if \(status\.budget <= 0 && status\.enabled\) startSession\(\)\s*else close\(\)/.test(plugin), 'Enter on the results goes again with no time left, and leaves otherwise')
assert(/statusPath: "\/var\/lib\/omarchy\/parent\/" \+ userName \+ "\/time\/status\.json"/.test(plugin), 'the plugin reads the account\'s root-owned status file')
assert(/import "\.\.\/math\/MathModel\.js" as MathGate/.test(service), 'the lock screen shares the math model')
assert(!/questionProc|answerProc|submitAnswer|timeGated/.test(service), 'the lock screen no longer asks questions')
assert(/command: \["omarchy-shell", "-q", "shell", "summon", "omarchy\.math", "\{\}"\]/.test(service), 'the lock screen summons the plugin through the shell')
const finishUnlock = service.match(/function finishUnlock\(\) \{[\s\S]*?\n  \}/)[0]
assert(/mathSummonPending = childInstall && timeGate\.enabled && timeGate\.gated/.test(finishUnlock), 'an unlock with no time left queues the math handoff')
assert(finishUnlock.indexOf('mathSummonPending =') < finishUnlock.indexOf('sessionLock.locked = false'), 'the handoff is queued before the session lock is released')
assert(!/summonMath\(\)/.test(finishUnlock), 'unlock does not summon a layer-shell surface during lock teardown')
assert(/function queueMathHandoff\(\) \{\s*if \(!mathSummonPending \|\| sessionLock\.locked \|\| sessionLock\.secure\) return\s*mathHandoffTimer\.restart\(\)/.test(service), 'the handoff waits for both lock states to clear')
assert(/onSecureStateChanged: \{[\s\S]*?root\.queueMathHandoff\(\)/.test(service), 'a secure-state release retries the pending handoff')
assert(/onLockStateChanged: \{[\s\S]*?root\.queueMathHandoff\(\)/.test(service), 'a lock-state release retries the pending handoff')
assert(/id: mathHandoffTimer\s*interval: 100\s*repeat: false\s*onTriggered: root\.completeMathHandoff\(\)/.test(service), 'the layer-shell surface gets a settling window after lock release')
assert(/function completeMathHandoff\(\) \{[\s\S]*?mathSummonPending = false[\s\S]*?logEvent\("math: summoned with no time left"\)[\s\S]*?summonMath\(\)/.test(service), 'the released session hands control to Math time once')
assert(/function beginLock\(\) \{[\s\S]*?mathSummonPending = false\s*mathHandoffTimer\.stop\(\)/.test(service), 'a relock cancels a pending math handoff')
assert(/onTimeStatusRawChanged: enforceTimeBudget\(\)/.test(service), 'a budget that runs out while unlocked still locks the session')
assert(/timeGate\.gated \? "No time left: unlock to do your math"/.test(service), 'the lock screen says what to do with no time left')
assert(!/mathQuestion|timeGated|digitsOnly/.test(view), 'the lock view has no question and no answer mode')
assert(/echoMode: TextInput\.Password/.test(view), 'the field is always a password field')
assert(/objectName: "timeLabel"/.test(view), 'the lock view still shows the banked time')
assert(/"math": \{[^}]*"when":"omarchy-profile-child && test -f \/var\/lib\/omarchy\/parent\/\$USER\/time\/enabled"[^}]*"action":"omarchy-shell shell summon omarchy\.math '\{\}'"/.test(menu), 'the menu offers Math time on a child install with screen time on')
JS
