// The lock screen's screen-time gate (plans/kids-screen-time.md), pure logic:
// what the root-owned helper prints, what the kid typed, and what the field
// should say. Root owns the budget and checks the answers; this only shapes
// the conversation. Loadable by Node for the tests and by QML for the view.

// omarchy-parent-quiz prints status.json: {"enabled":true,"budget":540,...}.
// Gated means the kid has to earn time before the password field returns.
function gateFromStatus(raw, childInstall) {
  var status = {}
  try {
    status = JSON.parse(String(raw || "")) || {}
  } catch (e) {
    status = {}
  }
  var enabled = !!status.enabled
  var budget = Number(status.budget) || 0
  if (budget < 0) budget = 0
  return {
    enabled: enabled,
    budget: budget,
    gated: !!childInstall && enabled && budget <= 0,
    earnedToday: Number(status.earnedToday) || 0,
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

if (typeof module !== "undefined") {
  module.exports = {
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
