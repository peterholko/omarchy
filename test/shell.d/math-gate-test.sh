#!/bin/bash
#
# The lock screen's screen-time gate reads what omarchy-parent-quiz prints and
# shapes the conversation with the kid. The logic is pure JavaScript shared
# with QML, so Node exercises it without a compositor.

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const gate = requireFromRoot('shell/plugins/lock/MathGateModel.js')

assertDeepEqual(gate.gateFromStatus('{"enabled":true,"school":false,"budget":0,"earnedToday":12,"cap":120}', true),
  { enabled: true, school: false, budget: 0, gated: true, earnedToday: 12, cap: 120 },
  'an empty budget on a child install gates the unlock')
assert(!gate.gateFromStatus('{"enabled":true,"school":true,"budget":0}', true).gated, 'school hours lift the gate at zero budget')
assert(!gate.gateFromStatus('{"enabled":true,"budget":0}', false).gated, 'a default install is never gated')
assert(!gate.gateFromStatus('{"enabled":false,"budget":0}', true).gated, 'screen time off never gates')
assert(!gate.gateFromStatus('{"enabled":true,"budget":60}', true).gated, 'banked time is not gated')
assert(!gate.gateFromStatus('not json', true).gated, 'unreadable status fails open to the password')
assertEqual(gate.gateFromStatus('{"enabled":true,"budget":-5}', true).budget, 0, 'a negative budget reads as empty')

assertDeepEqual(gate.parseQuestion('17 What is 342 + 519?'), { id: '17', text: 'What is 342 + 519?' }, 'a question line splits into id and text')
assertEqual(gate.parseQuestion('garbage'), null, 'a malformed question line is rejected')

assertEqual(gate.normalizeAnswer(' 1,234 '), '1234', 'answers drop commas and spaces')
assertEqual(gate.normalizeAnswer('12a3'), '123', 'answers keep digits only')

assertDeepEqual(gate.parseAnswer('correct 3 540'), { kind: 'correct', credited: 3, budget: 540 }, 'a correct answer carries its credit and the budget')
assertDeepEqual(gate.parseAnswer('wrong'), { kind: 'wrong', expected: '' }, 'a first wrong answer carries no reveal')
assertDeepEqual(gate.parseAnswer('wrong 861'), { kind: 'wrong', expected: '861' }, 'a second wrong answer reveals the expected value')
assertEqual(gate.parseAnswer('stale').kind, 'stale', 'a stale question is reported as such')
assertEqual(gate.parseAnswer('').kind, 'error', 'an empty reply is an error')

assertEqual(gate.feedback({ kind: 'correct', credited: 3, budget: 540 }), '+3 min. 9 min banked.', 'a credit says what was earned and what is banked')
assertEqual(gate.feedback({ kind: 'correct', credited: 0, budget: 0 }), "Right, but you have earned today's limit.", 'a capped credit explains itself')
assertEqual(gate.feedback({ kind: 'wrong', expected: '' }), 'Not quite, try again.', 'a first miss invites another try')
assertEqual(gate.feedback({ kind: 'wrong', expected: '861' }), 'The answer was 861. Next one.', 'a second miss shows the answer')

assert(!gate.needsNewQuestion({ kind: 'wrong', expected: '' }, true), 'a first miss keeps the question')
assert(gate.needsNewQuestion({ kind: 'wrong', expected: '861' }, true), 'a retired question is replaced')
assert(gate.needsNewQuestion({ kind: 'correct', credited: 3, budget: 180 }, true), 'while still gated a correct answer is followed by another question')
assert(!gate.needsNewQuestion({ kind: 'correct', credited: 3, budget: 180 }, false), 'once time is banked the questions stop')
assert(gate.needsNewQuestion({ kind: 'stale' }, true), 'a stale question is replaced')

assertEqual(gate.remainingLabel(540), '9 min left', 'remaining time rounds up to whole minutes')
assertEqual(gate.remainingLabel(0), 'No time left', 'an empty budget says so')
JS

# The wiring in the QML, asserted from source: the service reads root's
# status.json, asks and answers through the sudo grant with the exact argument
# lists it names, routes the field to the answer path while gated, refuses
# fingerprint while gated, and the view opens the field to digits.
run_node_test <<'JS'
const fs = require('fs')
const service = fs.readFileSync(path.join(root, 'shell/plugins/lock/Service.qml'), 'utf8')
const view = fs.readFileSync(path.join(root, 'shell/plugins/lock/LockView.qml'), 'utf8')

assert(/import "MathGateModel\.js" as MathGate/.test(service), 'the lock service loads the math-gate model')
assert(/timeStatusPath: "\/var\/lib\/omarchy\/parent\/" \+ userName \+ "\/time\/status\.json"/.test(service), 'the service watches the account\'s root-owned status file')
assert(/FileView \{\s*id: timeStatusView\s*path: root\.timeStatusPath\s*watchChanges: true/.test(service), 'status.json is watched for changes')
assert(/command: \["sudo", "-n", "\/usr\/bin\/omarchy-parent-quiz", "question"\]/.test(service), 'questions come through the sudo grant with the exact argument list')
assert(/Util\.shellQuote\(questionId\) \+ " " \+ Util\.shellQuote\(answer\) \+ " \| sudo -n \/usr\/bin\/omarchy-parent-quiz answer"/.test(service), 'answers travel over stdin to the granted answer form, quoted')
assert(/function submitPassword\(value\) \{[\s\S]*?if \(timeGated\) \{\s*submitAnswer\(password\)\s*return\s*\}/.test(service), 'while gated the field submits an answer, not a password')
assert(/function startFingerprint\(\) \{[\s\S]*?if \(timeGated\) return/.test(service), 'fingerprint is refused while gated')
assert(/readonly property bool timeGated: lockRequested && timeGate\.gated/.test(service), 'the gate applies only while locked')
assert(/if \(timeGate\.gated\) askQuestion\(\)/.test(service), 'locking with an empty budget asks a question')
assert(/onTimeStatusRawChanged: enforceTimeBudget\(\)/.test(service), 'a budget that runs out while unlocked locks the session')
assert(/\["omarchy-notification-send", "-u", "critical", "Screen time"/.test(service), 'running low warns through the notification helper')

assert(/echoMode: root\.timeGated \? TextInput\.Normal : TextInput\.Password/.test(view), 'the answer is typed in the open, the password masked')
assert(/inputMethodHints: root\.timeGated \? Qt\.ImhDigitsOnly : Qt\.ImhNone/.test(view), 'the answer field asks for digits')
assert(/validator: root\.timeGated \? digitsOnly : null/.test(view), 'the answer field accepts digits only')
assert(/objectName: "mathQuestion"[\s\S]*?visible: root\.timeGated && root\.questionText\.length > 0/.test(view), 'the question shows above the field while gated')
assert(/visible: root\.fingerprintConfigured && !root\.timeGated/.test(view), 'the fingerprint hint hides while gated')
assert(/gateMessage\.length > 0 \? gateMessage : "Your answer"/.test(view), 'the placeholder carries the verdict or the prompt')
JS
