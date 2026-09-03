// Math time (plans/kids-screen-time.md), the arithmetic app of a child
// install: pure logic shared by the QML view and the tests. Root's
// omarchy-parent-quiz owns the budget and checks the answers that earn time;
// a practice answer is checked here, against the answer the generator handed
// the app beside the question. Loadable by Node for the tests and by QML.

var GRADES = [1, 2, 3, 4, 5, 6]
var PRACTICE_COUNT = 10

// omarchy-parent-quiz prints status.json: {"enabled":true,"school":false,
// "budget":540,"level":"grade5",...}. Gated means the kid has to earn time
// before the desktop is hers; school hours lift the gate whatever the budget.
function gateFromStatus(raw, childInstall) {
  var status = {}
  try {
    status = JSON.parse(String(raw || "")) || {}
  } catch (e) {
    status = {}
  }
  var enabled = !!status.enabled
  var school = !!status.school
  var budget = Number(status.budget) || 0
  if (budget < 0) budget = 0
  var rate = Number(status.rate) || 6
  var questions = Number(status.questions) || 5
  return {
    enabled: enabled,
    school: school,
    budget: budget,
    gated: !!childInstall && enabled && !school && budget <= 0,
    earnedToday: Number(status.earnedToday) || 0,
    usedToday: Number(status.usedToday) || 0,
    rate: rate,
    questions: questions,
    sessionMinutes: Number(status.sessionMinutes) || rate * questions,
    cap: Number(status.cap) || 0,
    level: levelName(levelNumber(status.level))
  }
}

// Levels are grade1 to grade6 on the root side; the app thinks in numbers.
function levelNumber(level) {
  var match = String(level || "").match(/^grade([1-6])$/)
  return match ? Number(match[1]) : 5
}

function levelName(grade) {
  var n = Number(grade)
  if (!(n >= 1 && n <= 6)) n = 5
  return "grade" + n
}

function gradeLabel(grade) {
  return "Grade " + levelNumber(levelName(grade))
}

function gradeBlurb(grade) {
  switch (levelNumber(levelName(grade))) {
    case 1: return "Adding and taking away, up to 20"
    case 2: return "Adding and taking away up to 100, times 2 to 5"
    case 3: return "Times tables to 9 × 9, dividing, numbers to 1,000"
    case 4: return "Numbers to 10,000, hundreds times ones, long division"
    case 5: return "Large sums, two-digit times two-digit, exact division"
    default: return "Three-digit times two-digit, two-digit divisors, order of operations"
  }
}

// `question` prints "<id> <text>".
function parseQuestion(line) {
  var match = String(line || "").trim().match(/^(\d+)\s+(.+)$/)
  if (!match) return null
  return { id: match[1], text: match[2] }
}

// `practice` prints "<text>\t<answer>": the app checks these itself.
function parsePractice(line) {
  var parts = String(line || "").replace(/\r?\n$/, "").split("\t")
  if (parts.length < 2) return null
  var text = parts[0].trim()
  var answer = parts[1].trim()
  if (!text || !/^-?\d+$/.test(answer)) return null
  return { text: text, answer: answer }
}

// The field takes digits only; commas and spaces are stripped, so "1,234"
// and "1234" are the same answer.
function normalizeAnswer(text) {
  return String(text || "").replace(/[^0-9]/g, "")
}

// Omacalc sets both its application name and desktop-file name to `omacalc`.
// Match the Wayland app id without confusing it with other calculators.
function isCalculatorAppId(value) {
  var appId = String(value || "").trim().toLowerCase()
  return appId === "omacalc" || appId === "omacalc.desktop"
}

// `answer` prints "correct <minutes> <budget-seconds>", "wrong",
// "wrong <expected>", or "stale".
function parseAnswer(line) {
  var parts = String(line || "").trim().split(/\s+/)
  switch (parts[0]) {
    case "correct":
      return { kind: "correct", credited: Number(parts[1]) || 0, budget: Number(parts[2]) || 0 }
    case "wrong":
      return { kind: "wrong", expected: parts.length > 1 ? parts[1] : "" }
    case "stale":
      return { kind: "stale" }
    default:
      return { kind: "error" }
  }
}

// A practice answer, judged the way root judges an earning one: a first
// miss keeps the question, a second reveals the answer and moves on.
function judgePractice(answerText, expected, attempts) {
  var given = normalizeAnswer(answerText)
  if (given.length > 0 && Number(given) === Number(expected)) return { kind: "correct", credited: 0, budget: 0 }
  return { kind: "wrong", expected: (Number(attempts) || 0) + 1 >= 2 ? String(expected) : "" }
}

function minutes(seconds) {
  return Math.ceil((Number(seconds) || 0) / 60)
}

// The banner under the field after an answer. A right answer is just that,
// in either mode; the screen time it earned is told at the end of the set.
function feedbackFor(result, mode) {
  if (!result) return ""
  switch (result.kind) {
    case "correct":
      return "Correct!"
    case "wrong":
      return result.expected ? "The answer is " + result.expected + "." : "Not quite. Try once more."
    case "stale":
      return "That one timed out. Here is a fresh one."
    default:
      return "Could not check that. Press Enter to try again."
  }
}

function feedback(result) {
  return feedbackFor(result, "earn")
}

// After an answer: keep asking while still gated, and always after a stale,
// retired, or errored question. A wrong first attempt keeps the question.
function needsNewQuestion(result, gated) {
  if (!result) return true
  if (result.kind === "wrong" && !result.expected) return false
  return gated || result.kind !== "correct"
}

function remainingLabel(seconds) {
  var m = minutes(seconds)
  if (m <= 0) return "No time left"
  return m + " min left"
}

// A session is `total` questions; a question counts once it is answered
// right or retired after two misses. A stale one is replaced and not counted.
function questionDone(result) {
  if (!result) return false
  return result.kind === "correct" || (result.kind === "wrong" && !!result.expected)
}

function progressLabel(answered, total) {
  var n = Math.min(answered + 1, total)
  return "Question " + n + " of " + total
}

function streakLabel(streak) {
  var n = Number(streak) || 0
  return n >= 2 ? n + " in a row" : ""
}

function formatDuration(seconds) {
  var s = Math.max(0, Math.round(Number(seconds) || 0))
  var m = Math.floor(s / 60)
  if (m === 0) return s + " s"
  return m + " min " + (s % 60) + " s"
}

// What the results screen says once the set is done.
function resultsSummary(right, total, seconds, earnedMinutes, budgetSeconds) {
  var line = "You got " + right + " of " + total + " right in " + formatDuration(seconds) + "."
  if (earnedMinutes > 0) line += " +" + earnedMinutes + " min."
  else line += " No minutes this time."
  line += " " + minutes(budgetSeconds) + " min banked."
  return line
}

// The results screen, one line per fact: the score always, the best run when
// there was one, and, when the set was earning, the screen time it gained
// and what is banked now.
function sessionSummary(mode, right, total, seconds, earnedMinutes, budgetSeconds, bestStreak) {
  var lines = [right + " of " + total + " right in " + formatDuration(seconds)]
  if ((Number(bestStreak) || 0) >= 2) lines.push("Best run: " + bestStreak + " in a row")
  if (mode === "earn") {
    lines.push(earnedMinutes > 0 ? "+" + earnedMinutes + " min of screen time earned" : "No screen time earned this time")
    lines.push(minutes(budgetSeconds) + " min banked")
  }
  return lines
}

if (typeof module !== "undefined") {
  module.exports = {
    GRADES: GRADES,
    PRACTICE_COUNT: PRACTICE_COUNT,
    gateFromStatus: gateFromStatus,
    levelNumber: levelNumber,
    levelName: levelName,
    gradeLabel: gradeLabel,
    gradeBlurb: gradeBlurb,
    parseQuestion: parseQuestion,
    parsePractice: parsePractice,
    normalizeAnswer: normalizeAnswer,
    isCalculatorAppId: isCalculatorAppId,
    parseAnswer: parseAnswer,
    judgePractice: judgePractice,
    feedbackFor: feedbackFor,
    feedback: feedback,
    needsNewQuestion: needsNewQuestion,
    remainingLabel: remainingLabel,
    questionDone: questionDone,
    progressLabel: progressLabel,
    streakLabel: streakLabel,
    formatDuration: formatDuration,
    resultsSummary: resultsSummary,
    sessionSummary: sessionSummary,
    minutes: minutes
  }
}
