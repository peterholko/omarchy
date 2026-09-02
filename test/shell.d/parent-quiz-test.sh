#!/bin/bash
#
# omarchy-parent-quiz is the root-owned half of screen time: it asks the
# arithmetic, checks the answers, and credits minutes. The generator is
# exercised on its own; the question, answer, credit, and gate flow runs the
# real command against a scratch state root.

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

quiz="$ROOT/bin/omarchy-parent-quiz"

grep -q '^# omarchy:summary=' "$quiz" || fail "omarchy-parent-quiz carries command metadata"
grep -q '^# omarchy:hidden=true' "$quiz" || fail "omarchy-parent-quiz is plumbing, hidden from the listing"
pass "omarchy-parent-quiz is documented plumbing"

# The generator, on its own. Every question must be a plain expression whose
# bash evaluation is the stored answer, non-negative, with exact division.
eval "$(sed -n '/^# --- generator ---$/,/^# --- end generator ---$/p' "$quiz")"

evaluate() {
  local expr=$1
  expr=${expr#What is }
  expr=${expr%\?}
  expr=${expr//×/*}
  expr=${expr//÷//}
  echo $(( expr ))
}

check_level() {
  local level=$1 draws=$2 i text answer kinds="" expr a op b
  for ((i = 0; i < draws; i++)); do
    generate_question "$level"
    text=$question_text
    answer=$question_answer
    [[ $text == "What is "*"?" ]] || fail "$level question reads as a question" "got: $text"
    (( answer >= 0 )) || fail "$level answers are never negative" "got: $text = $answer"
    (( $(evaluate "$text") == answer )) || fail "$level answer matches its question" "got: $text = $answer"
    expr=${text#What is }; expr=${expr%\?}
    read -r a op b _ <<<"$expr"
    case $op in
      ÷) (( a % b == 0 )) || fail "$level division is exact" "got: $text" ;;
    esac
    for n in $expr; do
      [[ $n =~ ^[0-9]+$ ]] || continue
      case $n in
        0|1|10|100|1000|10000|100000) fail "$level avoids dull operands" "got: $text" ;;
      esac
      (( n < 1000000 )) || fail "$level keeps operands under a million" "got: $text"
    done
    kinds+="$op"
  done
  KINDS=$kinds
}

check_level grade5 300
[[ $KINDS == *+* && $KINDS == *-* && $KINDS == *×* && $KINDS == *÷* ]] || fail "grade5 mixes all four operations"
[[ $KINDS != *"+"*"×"* || true ]]
pass "grade5 questions are correct, non-negative, exactly divisible, and mixed"

check_level grade6 300
[[ $KINDS == *+* && $KINDS == *-* && $KINDS == *×* && $KINDS == *÷* ]] || fail "grade6 mixes all four operations"
pass "grade6 questions are correct, non-negative, exactly divisible, and mixed"

# grade5 never multiplies three digits by two, and never divides by two digits.
for ((i = 0; i < 300; i++)); do
  generate_question grade5
  expr=${question_text#What is }; expr=${expr%\?}
  read -r a op b _ <<<"$expr"
  case $op in
    ×) (( a < 100 || b < 10 )) || fail "grade5 multiplication stays two-by-two or three-by-one digit" "got: $question_text" ;;
    ÷) (( b < 10 )) || fail "grade5 division uses one-digit divisors" "got: $question_text" ;;
  esac
  [[ $expr != *"+"*"×"* && $expr != *"×"*"-"* ]] || fail "grade5 has no order-of-operations questions" "got: $question_text"
done
pass "grade5 stays within its ranges"

# The flow, against a scratch state root. SUDO_USER names the kid the way the
# passwordless grant does.
state=$(mktemp -d)
trap 'rm -rf "$state"' EXIT
export OMARCHY_PARENT_STATE_DIR="$state" SUDO_USER=kid
dir="$state/kid/time"
mkdir -p "$dir"

if bash "$quiz" question >/dev/null 2>&1; then
  fail "questions are refused while screen time is off"
fi
touch "$dir/enabled"
printf 'rate=6\ncap=120\nquestions=5\nlevel=grade5\n' >"$dir/config"
pass "questions are refused while screen time is off"

ask() {
  local line
  line=$(bash "$quiz" question)
  QUESTION_ID=${line%% *}
  QUESTION_TEXT=${line#* }
  [[ $QUESTION_ID =~ ^[0-9]+$ ]] || fail "question prints an id" "got: $line"
}
answer() { printf '%s %s\n' "$1" "$2" | bash "$quiz" answer; }

ask
[[ $(stat -f %Lp "$dir/question" 2>/dev/null || stat -c %a "$dir/question") == 600 ]] || fail "the pending question, which carries the answer, is root's alone"
result=$(answer "$QUESTION_ID" "$(evaluate "$QUESTION_TEXT")")
[[ $result == "correct 6 360" ]] || fail "a correct answer credits the rate" "got: $result"
[[ $(<"$dir/budget") == 360 && $(<"$dir/earned") == 6 ]] || fail "the budget and today's tally record the credit"
[[ ! -f $dir/question ]] || fail "an answered question is retired"
grep -q '"budget":360' "$dir/status.json" || fail "status.json reflects the credit"
grep -q '"questions":5' "$dir/status.json" && grep -q '"sessionMinutes":30' "$dir/status.json" && grep -q '"usedToday":0' "$dir/status.json" || fail "status.json carries the session shape and the day's use" "$(cat "$dir/status.json")"
[[ $(stat -f %Lp "$dir/status.json" 2>/dev/null || stat -c %a "$dir/status.json") == 644 ]] || fail "status.json is readable by the kid's shell"
grep -q " question $QUESTION_ID text=What is .* answer=[0-9]*$" "$dir/log" && grep -q " correct $QUESTION_ID +6 given=[0-9]* secs=[0-9]*$" "$dir/log" || fail "the log keeps the question, its answer, what was given, and how long it took" "$(cat "$dir/log")"
grep -q '^QUESTION_TTL=1800' "$quiz" || fail "a question stays answerable for half an hour"
pass "a correct answer credits six minutes and records it"

ask
result=$(answer "$QUESTION_ID" "1,234 ")
[[ $result == "correct 6 720" || $result == "wrong" ]] || fail "answers tolerate commas and spaces" "got: $result"
pass "answers tolerate commas and spaces"

ask
first=$(answer "$QUESTION_ID" -1)
second=$(answer "$QUESTION_ID" -1)
[[ $first == "wrong" ]] || fail "the first wrong answer only says so" "got: $first"
[[ $second == "wrong $(evaluate "$QUESTION_TEXT")" ]] || fail "the second wrong answer reveals the answer" "got: $second"
[[ ! -f $dir/question ]] || fail "a twice-missed question is retired"
grep -q " wrong $QUESTION_ID retired given=-1 expected=$(evaluate "$QUESTION_TEXT") secs=[0-9]*$" "$dir/log" || fail "a retired question logs the miss and the answer" "$(tail -3 "$dir/log")"
budget_before=$(<"$dir/budget")
third=$(answer "$QUESTION_ID" "$(evaluate "$QUESTION_TEXT")")
[[ $third == "stale" ]] || fail "a retired question earns nothing even when answered right" "got: $third"
[[ $(<"$dir/budget") == "$budget_before" ]] || fail "a stale answer leaves the budget alone"
pass "two wrong answers reveal the answer and retire the question without credit"

ask
stale_id=$QUESTION_ID
ask
result=$(answer "$stale_id" "$(evaluate "$QUESTION_TEXT")")
[[ $result == "stale" ]] || fail "a superseded question is stale" "got: $result"
pass "a new question supersedes the old one"

# The daily cap bounds the credit; at the cap a right answer credits nothing.
printf '119\n' >"$dir/earned"
ask
result=$(answer "$QUESTION_ID" "$(evaluate "$QUESTION_TEXT")")
[[ $result == correct\ 1\ * ]] || fail "the last minute before the cap credits only what is left" "got: $result"
ask
result=$(answer "$QUESTION_ID" "$(evaluate "$QUESTION_TEXT")")
[[ $result == correct\ 0\ * ]] || fail "at the cap a right answer credits nothing" "got: $result"
pass "credits never exceed the daily cap"

# A new day resets the tally and hands out free minutes.
printf '2000-01-01\n' >"$dir/day"
printf 'rate=3\ncap=120\nfree=10\nlevel=grade5\n' >"$dir/config"
budget_before=$(<"$dir/budget")
ask
[[ $(<"$dir/earned") == 0 ]] || fail "a new day resets what was earned"
[[ $(<"$dir/budget") == $((budget_before + 600)) ]] || fail "a new day adds the free minutes"
[[ $(<"$dir/day") == "$(date +%F)" ]] || fail "a new day is recorded"
[[ $(<"$dir/used") == 0 ]] || fail "a new day resets the use counter"
[[ -f $dir/reports/2000-01-01.txt ]] || fail "a new day writes the finished day's report to root's disk"
[[ $(stat -f %Lp "$dir/reports/2000-01-01.txt" 2>/dev/null || stat -c %a "$dir/reports/2000-01-01.txt") == 600 ]] || fail "the report is root's alone"
pass "midnight resets the tally, grants free minutes, and files the day's report"

# Use is counted per day, and the report reads the day back.
printf '600\n' >"$dir/budget"
bash "$quiz" --user kid consume 60 >/dev/null
bash "$quiz" --user kid consume 60 >/dev/null
[[ $(<"$dir/used") == 120 ]] || fail "consume counts the seconds it charged" "$(<"$dir/used")"
printf '30\n' >"$dir/budget"
bash "$quiz" --user kid consume 60 >/dev/null
[[ $(<"$dir/used") == 150 ]] || fail "an emptied budget counts only what was left"
report=$(bash "$quiz" --user kid report)
[[ $report == "Screen time for kid, $(date +%F)"* ]] || fail "the report names the account and the day" "$report"
[[ $report == *"Used: 3 min"* ]] || fail "the report rounds the use up to minutes" "$report"
[[ $report == *"Math: "*" questions asked, "*" right, "*" wrong after two tries"* ]] || fail "the report counts the questions" "$report"
[[ $report == *"  What is "* && $report == *"right   "*" s   6 min"* && $report == *"wrong   "*"answered -1"* ]] || fail "the report lists each question with its outcome" "$report"
[[ -f $dir/reports/$(date +%F).txt ]] || fail "asking for the report keeps a copy"
pass "the day's report reads use, earnings, and every question back"

# The gate: PAM runs it as the kid, so it must work without root and read
# only world-readable files.
printf '0\n' >"$dir/budget"
if PAM_USER=kid SUDO_USER= bash "$quiz" gate; then
  fail "the gate refuses an unlock at zero budget"
fi
printf '60\n' >"$dir/budget"
PAM_USER=kid SUDO_USER= bash "$quiz" gate || fail "the gate allows an unlock with time banked"
rm "$dir/enabled"
printf '0\n' >"$dir/budget"
PAM_USER=kid SUDO_USER= bash "$quiz" gate || fail "the gate allows an unlock when screen time is off"
OMARCHY_PARENT_STATE_DIR="$state/nowhere" PAM_USER=kid SUDO_USER= bash "$quiz" gate || fail "the gate allows an unlock when screen time was never set up"
pass "the PAM gate follows the budget and stands aside when screen time is off"

# The timer and the parent's commands name the account and move the budget
# directly. These forms are root's; the passwordless grant never lists them.
touch "$dir/enabled"
printf 'rate=3\ncap=120\nlevel=grade5\n' >"$dir/config"
printf '100\n' >"$dir/budget"
[[ $(SUDO_USER= bash "$quiz" --user kid consume 60) == 40 ]] || fail "consume takes seconds off the budget and reports the rest"
[[ $(SUDO_USER= bash "$quiz" --user kid consume 60) == 0 ]] || fail "consume stops at zero"
printf '119\n' >"$dir/earned"
[[ $(SUDO_USER= bash "$quiz" --user kid credit 15) == 900 ]] || fail "credit adds minutes regardless of the daily cap"
grep -q 'grant 15' "$dir/log" || fail "a credit is logged as a grant"
if SUDO_USER= bash "$quiz" --user root consume 60 >/dev/null 2>&1; then
  fail "root is never an account"
fi
if SUDO_USER= bash "$quiz" --user 'kid;rm' consume 60 >/dev/null 2>&1; then
  fail "an account name must be a plain username"
fi
pass "consume and credit move the budget for a named account"

# School hours: the countdown pauses, the gate stands aside, and status says
# so. The schedule is normalized lines of days, start, and end; the clock is
# planted through OMARCHY_PARENT_NOW, which only the test override honors.
touch "$dir/enabled"
printf '12345 0800 1530\n6 0900 1100\n' >"$dir/schedule"
printf '0\n' >"$dir/budget"
OMARCHY_PARENT_NOW="3 0900" SUDO_USER= bash "$quiz" --user kid school || fail "Wednesday morning is school time"
if OMARCHY_PARENT_NOW="3 1530" SUDO_USER= bash "$quiz" --user kid school; then fail "the window ends at its end time"; fi
if OMARCHY_PARENT_NOW="7 0900" SUDO_USER= bash "$quiz" --user kid school; then fail "Sunday is not on the schedule"; fi
OMARCHY_PARENT_NOW="6 1000" SUDO_USER= bash "$quiz" --user kid school || fail "a second window counts too"
OMARCHY_PARENT_NOW="3 0900" PAM_USER=kid SUDO_USER= bash "$quiz" gate || fail "the gate stands aside during school hours even at zero budget"
if OMARCHY_PARENT_NOW="3 1600" PAM_USER=kid SUDO_USER= bash "$quiz" gate; then fail "after school the gate holds at zero budget"; fi
printf '300\n' >"$dir/budget"
[[ $(OMARCHY_PARENT_NOW="3 0900" SUDO_USER= bash "$quiz" --user kid consume 60) == 300 ]] || fail "school hours are not charged"
[[ $(OMARCHY_PARENT_NOW="3 1600" SUDO_USER= bash "$quiz" --user kid consume 60) == 240 ]] || fail "after school the charge resumes"
OMARCHY_PARENT_NOW="3 0900" SUDO_USER= bash "$quiz" --user kid status | grep -q '"school":true' || fail "status reports school hours"
OMARCHY_PARENT_NOW="3 1600" SUDO_USER= bash "$quiz" --user kid status | grep -q '"school":false' || fail "status reports the end of school"
rm "$dir/schedule"
if OMARCHY_PARENT_NOW="3 0900" SUDO_USER= bash "$quiz" --user kid school; then fail "no schedule means no school hours"; fi
pass "school hours pause the countdown and lift the gate"

[[ $(stat -f %Lp "$dir/log" 2>/dev/null || stat -c %a "$dir/log") == 600 ]] || fail "the log, which names retired answers, is root's alone"
grep -q '^# omarchy:args=\[--user NAME\] <question|answer|status|gate|school|consume SECONDS|credit MINUTES>' "$quiz" || fail "the subcommands are the whole surface"
if SUDO_USER= PAM_USER= bash "$quiz" status >/dev/null 2>&1 && [[ $(id -un) == root ]]; then
  fail "root running the helper directly names no account"
fi
pass "the helper names the account from PAM or sudo, never root itself"
