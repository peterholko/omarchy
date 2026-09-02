// The lock screen's screen-time gate (plans/kids-screen-time.md), pure logic:
// what the root-owned helper prints, what the kid typed, and what the field
// should say. Root owns the budget and checks the answers; this only shapes
// the conversation. Loadable by Node for the tests and by QML for the view.

// omarchy-parent-quiz prints status.json: {"enabled":true,"school":false,
// "budget":540,...}. Gated means the kid has to earn time before the password
// field returns; school hours lift the gate whatever the budget.
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
    cap: Number(status.cap) || 0
  }
}

// `question` prints "<id> <text>".
function parseQuestion(line) {
  var match = String(line || "").trim().match(/^(\d+)\s+(.+)$/)
  if (!match) return null
  return { id: match[1], text: match[2] }
}

// The field takes digits only; commas and spaces are stripped, so "1,234"
// and "1234" are the same answer.
function normalizeAnswer(text) {
  return String(text || "").replace(/[^0-9]/g, "")
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

function minutes(seconds) {
  return Math.ceil((Number(seconds) || 0) / 60)
}

// What the line under the field says after an answer.
function feedback(result) {
  if (!result) return ""
  switch (result.kind) {
    case "correct":
      if (result.credited <= 0) return "Right, but you have earned today's limit."
      return "+" + result.credited + " min. " + minutes(result.budget) + " min banked."
    case "wrong":
      return result.expected ? "The answer was " + result.expected + ". Next one." : "Not quite, try again."
    case "stale":
      return "That one expired. Here is another."
    default:
      return "Could not check that answer."
  }
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

// A session is `questions` questions; a question counts once it is answered
// right or retired after two misses. A stale one is replaced and not counted.
function questionDone(result) {
  if (!result) return false
  return result.kind === "correct" || (result.kind === "wrong" && !!result.expected)
}

function progressLabel(answered, total) {
  var n = Math.min(answered + 1, total)
  return "Question " + n + " of " + total
}

function formatDuration(seconds) {
  var s = Math.max(0, Math.round(Number(seconds) || 0))
  var m = Math.floor(s / 60)
  if (m === 0) return s + " s"
  return m + " min " + (s % 60) + " s"
}

// What the results screen says once the batch is done.
function resultsSummary(right, total, seconds, earnedMinutes, budgetSeconds) {
  var line = "You got " + right + " of " + total + " right in " + formatDuration(seconds) + "."
  if (earnedMinutes > 0) line += " +" + earnedMinutes + " min."
  else line += " No minutes this time."
  line += " " + minutes(budgetSeconds) + " min banked."
  return line
}

if (typeof module !== "undefined") {
  module.exports = {
    questionDone: questionDone,
    progressLabel: progressLabel,
    formatDuration: formatDuration,
    resultsSummary: resultsSummary,
    gateFromStatus: gateFromStatus,
    parseQuestion: parseQuestion,
    normalizeAnswer: normalizeAnswer,
    parseAnswer: parseAnswer,
    feedback: feedback,
    needsNewQuestion: needsNewQuestion,
    remainingLabel: remainingLabel,
    minutes: minutes
  }
}
