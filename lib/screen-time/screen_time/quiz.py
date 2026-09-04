"""Questions that buy minutes, at a grade.

Two rules shape this file. The answer is never sent to the client, because the
client runs on the child's own machine and a text editor is not a challenge.
And the questions are weighted by what went wrong before, so the fact that is
actually missing comes back around instead of the one they already know.

The grades are Omarchy's own (plans/kids-screen-time.md): grade 1 adds and
takes away within 20; grade 2 within 100, with the tables of 2 to 5; grade 3
the tables to 9 × 9, their divisions, and sums to a thousand; grade 4 keeps
questions and answers within three digits; grades 5 and 6 keep them within
four, with grade 6 adding two-digit divisors and order of operations. A
question is a kind (which arithmetic) and its operands; small facts, the
tables, are weighted one by one, and the big-number kinds by kind, since their
exact operands rarely come round twice.
"""

import random
import secrets
import time

DULL = {0, 1, 10, 100, 1000, 10000, 100000}

# kind -> weight, per grade; the roll picks a kind, then the operands.
GRADES = {
    "grade1": [("add20", 55), ("sub20", 45)],
    "grade2": [("add100", 40), ("sub100", 35), ("mulsmall", 25)],
    "grade3": [("add1000", 25), ("sub1000", 20), ("table", 30), ("tablediv", 25)],
    "grade4": [("add1000", 25), ("sub1000", 20), ("mul2x1", 30), ("div1", 25)],
    "grade5": [("add10000", 25), ("sub10000", 25), ("mul2x2", 25), ("div1", 25)],
    "grade6": [("add10000", 15), ("sub10000", 15), ("mul2x2", 15), ("mul3x1", 15),
               ("div1", 10), ("div2", 15), ("ops", 15)],
}

# The kinds whose operands are few enough to be remembered one by one.
FACT_KINDS = {"add20", "sub20", "mulsmall", "table", "tablediv"}


def _key(kind, text):
    return f"{kind}:{text}"


class Question:
    __slots__ = ("id", "kind", "text", "answer", "key", "issued_at")

    def __init__(self, kind, text, answer, issued_at, fact=False):
        self.id = secrets.token_hex(8)
        self.kind = kind
        self.text = text
        self.answer = answer
        # Facts are remembered by their operands, the rest by their kind.
        self.key = _key(kind, text) if fact else kind
        self.issued_at = issued_at

    def public(self, reward_seconds, timeout_seconds):
        return {
            "id": self.id,
            "text": self.text,
            "kind": self.kind,
            "reward_seconds": reward_seconds,
            "timeout_seconds": timeout_seconds,
        }


class Generator:
    """One question at a grade. Shared by the earning quiz and practice."""

    def __init__(self, rng=None):
        self.rng = rng or random.Random()

    def pick(self, lo, hi):
        """An operand in [lo, hi], never a dull one (0, 1, powers of ten)."""
        if hi < lo:
            hi = lo
        candidates = [n for n in range(lo, hi + 1) if n not in DULL]
        if not candidates:
            return lo
        return self.rng.choice(candidates)

    def product(self, lo_a, hi_a, lo_b, hi_b):
        """Two operands whose product is not dull, for the divisions."""
        for _ in range(50):
            b = self.pick(lo_a, hi_a)
            c = self.pick(lo_b, hi_b)
            if b * c not in DULL:
                return b, c
        return b, c

    def make(self, kind):
        """(text, answer) for a kind. Every text is "a op b", plain."""
        p = self.pick
        if kind == "add20":
            a = p(2, 18); b = p(2, 20 - a); return f"{a} + {b}", a + b
        if kind == "sub20":
            a = p(4, 20); b = p(2, a - 2); return f"{a} - {b}", a - b
        if kind == "add100":
            a = p(11, 88); b = p(11, 99 - a); return f"{a} + {b}", a + b
        if kind == "sub100":
            a = p(25, 99); b = p(11, a - 2); return f"{a} - {b}", a - b
        if kind == "mulsmall":
            a = p(2, 5); b = p(2, 9); return f"{a} × {b}", a * b
        if kind == "add1000":
            a = p(101, 898); b = p(101, 999 - a); return f"{a} + {b}", a + b
        if kind == "sub1000":
            a = p(201, 999); b = p(101, a - 2); return f"{a} - {b}", a - b
        if kind == "table":
            a = p(2, 9); b = p(2, 9); return f"{a} × {b}", a * b
        if kind == "tablediv":
            b, c = self.product(2, 9, 2, 9); return f"{b * c} ÷ {b}", c
        if kind == "add10000":
            a = p(1001, 8998); b = p(1001, 9999 - a); return f"{a} + {b}", a + b
        if kind == "sub10000":
            a = p(2001, 9999); b = p(1001, a - 2); return f"{a} - {b}", a - b
        if kind == "mul2x1":
            a = p(12, 99); b = p(2, 9); return f"{a} × {b}", a * b
        if kind == "mul2x2":
            a = p(12, 99); b = p(12, 99); return f"{a} × {b}", a * b
        if kind == "mul3x1":
            a = p(101, 999); b = p(2, 9); return f"{a} × {b}", a * b
        if kind == "div1":
            b, c = self.product(2, 9, 12, 99); return f"{b * c} ÷ {b}", c
        if kind == "div2":
            b, c = self.product(12, 99, 2, 9); return f"{b * c} ÷ {b}", c
        if kind == "ops":
            b = p(2, 12); c = p(2, 12)
            if self.rng.random() < 0.5:
                a = p(2, 50); return f"{a} + {b} × {c}", a + b * c
            a = p(2, b * c - 1); return f"{b} × {c} - {a}", b * c - a
        raise ValueError(f"unknown kind {kind}")

    def question(self, level, now=None, weights=None):
        kinds = GRADES.get(level) or GRADES["grade5"]
        pool = [k for k, _ in kinds]
        base = [w for _, w in kinds]
        if weights:
            base = [b * weights.get(k, 1.0) for b, k in zip(base, pool)]
        kind = self.rng.choices(pool, weights=base, k=1)[0]
        text, answer = self.make(kind)
        return Question(kind, text, answer, now or time.time(), fact=kind in FACT_KINDS)


def practice(level, rng=None):
    """A question with its answer, for practice: checked by the app, recorded by nobody."""
    q = Generator(rng).question(level, 0)
    return {"text": q.text, "answer": q.answer, "kind": q.kind}


class Quiz:
    """Generates earning questions for one account and remembers how it went."""

    def __init__(self, earn_config, stats=None, rng=None):
        self.config = earn_config
        self.stats = stats if isinstance(stats, dict) else {}
        self.generator = Generator(rng)
        self.pending = None
        self.last_key = None

    def _weight(self, key):
        record = self.stats.get(key) or {}
        seen = max(0, int(record.get("seen", 0)))
        wrong = max(0, int(record.get("wrong", 0)))
        weight = 1.0
        if self.config.get("drill_weak") and seen:
            weight += 4.0 * (wrong / seen)
            if record.get("last_wrong") and time.time() - record["last_wrong"] < 86400:
                weight += 2.0
        return weight

    def next_question(self, now=None):
        now = now or time.time()
        level = self.config.get("level", "grade5")
        kind_weights = {k: self._weight(k) for k, _ in GRADES.get(level, GRADES["grade5"])}
        # A fact that went wrong comes back: the kind it belongs to is drawn
        # more often, and within the kind the fact itself is drawn again.
        question = None
        for _ in range(8):
            candidate = self.generator.question(level, now, kind_weights)
            if candidate.key == self.last_key:
                question = question or candidate
                continue
            question = candidate
            if not self.config.get("drill_weak") or self._weight(candidate.key) > 1.0:
                break
        self.pending = question
        self.last_key = question.key
        return question

    # answering ----------------------------------------------------------

    def answer(self, question_id, given, now=None):
        """Judge an answer. Returns a verdict dict; never leaks the answer of a
        question that is still open."""
        now = now or time.time()
        question = self.pending
        if not question or question.id != question_id:
            return {"ok": False, "error": "no_such_question"}

        elapsed = now - question.issued_at
        if elapsed > self.config["question_timeout_seconds"]:
            self.pending = None
            return {"ok": False, "error": "expired", "text": question.text}

        try:
            value = int(str(given).strip().replace(",", "").replace(" ", ""))
        except (TypeError, ValueError):
            return {"ok": False, "error": "not_a_number"}

        if elapsed < self.config["min_answer_seconds"]:
            return {"ok": False, "error": "too_fast",
                    "wait_seconds": round(self.config["min_answer_seconds"] - elapsed, 1)}

        correct = value == question.answer
        self._record(question, correct, now)
        self.pending = None
        return {
            "ok": True,
            "correct": correct,
            "text": question.text,
            "answer": question.answer,
            "given": value,
            "seconds_taken": round(elapsed, 1),
        }

    def _record(self, question, correct, now):
        record = self.stats.setdefault(question.key, {"seen": 0, "wrong": 0})
        record["seen"] = int(record.get("seen", 0)) + 1
        if not correct:
            record["wrong"] = int(record.get("wrong", 0)) + 1
            record["last_wrong"] = round(now, 1)

    def weakest(self, limit=5):
        """The facts and kinds worth practising, for the parent."""
        rows = []
        for key, record in self.stats.items():
            seen = int(record.get("seen", 0))
            wrong = int(record.get("wrong", 0))
            if seen >= 2 and wrong:
                text = key.split(":", 1)[1] if ":" in key else key
                rows.append({"text": text, "seen": seen, "wrong": wrong, "rate": round(wrong / seen, 2)})
        rows.sort(key=lambda row: (row["rate"], row["wrong"]), reverse=True)
        return rows[:limit]
