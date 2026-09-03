#!/bin/bash
#
# omarchy-parent-llm is the observe-only LLM prompt log for a child install:
# a parent-gated collector, a Chromium extension, and daily markdown under
# the root account. The static half pins the contract from the source; the
# collector and report are exercised against scratch files; on/off runs as
# namespaced root where the kernel allows it.

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command python3

llm="$ROOT/bin/omarchy-parent-llm"
collect="$ROOT/bin/omarchy-parent-llm-collect"
host="$ROOT/bin/omarchy-parent-llm-host"
menu="$ROOT/default/omarchy/omarchy-menu.jsonc"
manifest="$ROOT/default/chromium/extensions/llm-monitor/manifest.json"
native_template="$ROOT/default/chromium/native-messaging-hosts/com.omarchy.parent_llm.json"

grep -q '^# omarchy:summary=Log LLM prompts on a child install (observe only)' "$llm" ||
  fail "omarchy-parent-llm carries a summary"
grep -q '^# omarchy:requires-sudo=true' "$llm" || fail "omarchy-parent-llm requires sudo"
grep -q '^# omarchy:hidden=true' "$collect" || fail "the collector is hidden plumbing"
grep -q '^# omarchy:hidden=true' "$host" || fail "the native messaging host is hidden plumbing"
pass "omarchy-parent-llm and its plumbing carry command metadata"

help_output=$(bash "$llm" --help)
[[ $help_output == *"omarchy-parent llm on"* && $help_output == *"/root/llm-reports"* ]] ||
  fail "omarchy-parent-llm --help prints usage without elevating" "$help_output"
pass "omarchy-parent-llm answers --help before asking for a password"

parent_help=$(OMARCHY_PATH="$ROOT" bash "$ROOT/bin/omarchy-parent" --help)
[[ $parent_help == *"llm "* && $parent_help == *"Log LLM prompts on a child install"* ]] ||
  fail "omarchy-parent --help lists the llm feature" "$parent_help"
[[ $parent_help != *llm-host* && $parent_help != *llm-collect* ]] ||
  fail "omarchy-parent --help hides llm plumbing" "$parent_help"
pass "omarchy-parent lists llm as a feature command"

[[ -f $ROOT/default/parent/llm-hosts.txt ]] || fail "the default host list ships"
[[ -f $ROOT/default/parent/systemd/omarchy-parent-llm.socket ]] || fail "the socket unit template ships"
[[ -f $ROOT/default/parent/systemd/omarchy-parent-llm@.service ]] || fail "the connection unit template ships"
grep -q 'ListenStream=/run/omarchy-parent-llm.sock' "$ROOT/default/parent/systemd/omarchy-parent-llm.socket" ||
  fail "the socket unit listens on /run/omarchy-parent-llm.sock"
pass "collector unit templates and the host list ship"

grep -q '"update.llm-log": {[^}]*"when":"omarchy-profile-child"' "$menu" ||
  fail "LLM log stays off a non-child menu"
grep -q '"update.llm-log.on": {[^}]*omarchy-parent llm on' "$menu" ||
  fail "LLM log On runs omarchy-parent llm on"
grep -q '"update.llm-log.report": {[^}]*omarchy-parent llm report' "$menu" ||
  fail "LLM log Today's report runs omarchy-parent llm report"
pass "the menu offers the LLM log only on a child install"

python3 - "$manifest" "$native_template" <<'PY'
import base64, hashlib, json, sys
from pathlib import Path

manifest = json.loads(Path(sys.argv[1]).read_text())
template = Path(sys.argv[2]).read_text()
der = base64.b64decode(manifest["key"])
ext_id = "".join(chr(ord("a") + (byte >> 4)) + chr(ord("a") + (byte & 0x0F)) for byte in hashlib.sha256(der).digest()[:16])
origin = f"chrome-extension://{ext_id}/"
if origin not in template:
  raise SystemExit(f"native host template does not allow {origin}")
if "nativeMessaging" not in manifest.get("permissions", []):
  raise SystemExit("extension is missing nativeMessaging")
if "chatgpt.com/*" not in " ".join(manifest.get("host_permissions", [])):
  raise SystemExit("extension is missing chatgpt.com")
PY
pass "the extension id matches the native messaging host"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
journal="$tmp/journal.jsonl"
reports="$tmp/reports"
mkdir -p "$reports"

append_prompt() {
  local payload=$1
  python3 "$collect" append --journal "$journal" --user kid <<<"$payload"
}

append_prompt '{"source":"browser","host":"chatgpt.com","url":"https://chatgpt.com/c/abc?token=secret","prompt":"Write a 5-paragraph essay on photosynthesis"}'
append_prompt '{"source":"browser","host":"chatgpt.com","url":"https://chatgpt.com/c/abc?token=secret","prompt":"Write a 5-paragraph essay on photosynthesis"}'
append_prompt '{"source":"browser","host":"claude.ai","url":"https://claude.ai/chat/1","prompt":"finish this paragraph","attachments":2}'
append_prompt '{"source":"cli","tool":"claude","prompt":"rewrite src/main.py and add comments"}'

python3 - "$journal" <<'PY'
import json, sys
from pathlib import Path
from urllib.parse import urlparse

lines = [json.loads(line) for line in Path(sys.argv[1]).read_text().splitlines() if line.strip()]
if len(lines) != 3:
  raise SystemExit(f"expected 3 journal lines after dedup, got {len(lines)}")
if lines[0]["prompt"] != "Write a 5-paragraph essay on photosynthesis":
  raise SystemExit("first prompt was not kept")
if "token=secret" in lines[0].get("url", ""):
  raise SystemExit("query tokens were not stripped from the url")
if lines[1]["attachments"] != 2:
  raise SystemExit("attachment count was dropped")
if lines[2]["source"] != "cli" or lines[2]["tool"] != "claude":
  raise SystemExit("cli event missing tool")
PY
pass "the collector appends, dedups, strips query tokens, and keeps attachment counts"

python3 "$collect" report --journal "$journal" --out-dir "$reports" --user ada --print >/dev/null
today=$(date +%F)
[[ -f $reports/$today.md ]] || fail "report writes YYYY-MM-DD.md"
report=$(<"$reports/$today.md")
[[ $report == *"LLM prompt report — ada — $today"* ]] || fail "report header names the user and day" "$report"
[[ $report == *"## chatgpt.com (1)"* ]] || fail "report groups chatgpt.com" "$report"
[[ $report == *"## claude.ai (1)"* ]] || fail "report groups claude.ai" "$report"
[[ $report == *"[2 attachments]"* ]] || fail "report mentions attachments" "$report"
[[ $report == *"### claude (1)"* ]] || fail "report groups CLI claude" "$report"
[[ $report == *"rewrite src/main.py"* ]] || fail "report includes the CLI prompt" "$report"
[[ -L $reports/latest.md || -f $reports/latest.md ]] || fail "report writes latest.md"
python3 - "$reports/$today.md" <<'PY'
import os, stat, sys
mode = stat.S_IMODE(os.stat(sys.argv[1]).st_mode)
if mode != 0o600:
  raise SystemExit(f"report mode is {oct(mode)}, expected 0o600")
PY
pass "the daily report groups prompts and is mode 600"

empty_journal="$tmp/empty.jsonl"
: >"$empty_journal"
python3 "$collect" report --journal "$empty_journal" --out-dir "$tmp/empty-reports" --user kid --date 2026-01-01 >/dev/null
[[ -f $tmp/empty-reports/2026-01-01.md ]] || fail "an empty day still writes a report"
grep -q "No prompts captured" "$tmp/empty-reports/2026-01-01.md" || fail "an empty day says so"
pass "an empty day still writes a report file"

home="$tmp/home"
mkdir -p "$home/.claude/projects/essay"
python3 - "$home" <<'PY'
from datetime import datetime, timezone
from pathlib import Path
import json, sys

home = Path(sys.argv[1])
now = datetime.now().astimezone().isoformat(timespec="seconds")
path = home / ".claude" / "projects" / "essay" / "session.jsonl"
path.write_text(
  json.dumps({"type": "user", "timestamp": now, "message": {"role": "user", "content": [{"type": "text", "text": "write my history essay"}]}})
  + "\n"
  + json.dumps({"type": "assistant", "timestamp": now, "message": {"role": "assistant", "content": [{"type": "text", "text": "here is the essay"}]}})
  + "\n"
)
PY
cli_journal="$tmp/cli-journal.jsonl"
python3 "$collect" harvest --journal "$cli_journal" --user kid --home "$home" >/dev/null
python3 - "$cli_journal" <<'PY'
import json, sys
from pathlib import Path
lines = [json.loads(line) for line in Path(sys.argv[1]).read_text().splitlines() if line.strip()]
if len(lines) != 1:
  raise SystemExit(f"expected 1 harvested user turn, got {len(lines)}: {lines}")
if lines[0]["source"] != "cli" or lines[0]["tool"] != "claude":
  raise SystemExit(f"harvested event is not a claude cli turn: {lines[0]}")
if "write my history essay" not in lines[0]["prompt"]:
  raise SystemExit("user prompt missing")
if "here is the essay" in lines[0]["prompt"]:
  raise SystemExit("assistant turn was harvested")
PY
pass "CLI harvest keeps user turns and drops assistant turns"

mkdir -p "$home/.config/chromium/Default"
python3 - "$home" "$ROOT/default/parent/llm-hosts.txt" <<'PY'
import sqlite3, time, sys
from pathlib import Path

home = Path(sys.argv[1])
hosts_file = Path(sys.argv[2])
chrome_now = int((time.time() + 11_644_473_600) * 1_000_000)
history = home / ".config" / "chromium" / "Default" / "History"
conn = sqlite3.connect(history)
conn.executescript("""
CREATE TABLE urls (id INTEGER PRIMARY KEY, url TEXT, title TEXT, visit_count INTEGER, last_visit_time INTEGER);
CREATE TABLE visits (id INTEGER PRIMARY KEY, url INTEGER, visit_time INTEGER);
""")
conn.execute("INSERT INTO urls VALUES (1, 'https://chatgpt.com/', 'ChatGPT', 4, ?)", (chrome_now,))
conn.execute("INSERT INTO urls VALUES (2, 'https://example.com/', 'Example', 9, ?)", (chrome_now,))
conn.execute("INSERT INTO visits VALUES (1, 1, ?)", (chrome_now,))
conn.execute("INSERT INTO visits VALUES (2, 1, ?)", (chrome_now,))
conn.commit()
conn.close()
PY
export OMARCHY_PARENT_LLM_HOSTS="$ROOT/default/parent/llm-hosts.txt"
export OMARCHY_PARENT_LLM_STATE="$tmp/state"
mkdir -p "$tmp/state"
python3 "$collect" harvest --journal "$cli_journal" --user kid --home "$home" >/dev/null
python3 - "$tmp/state" <<'PY'
import json, sys
from pathlib import Path
from datetime import datetime
day = datetime.now().strftime("%Y-%m-%d")
visits = json.loads((Path(sys.argv[1]) / f"visits-{day}.json").read_text())
if visits.get("chatgpt.com") != 2:
  raise SystemExit(f"expected 2 chatgpt.com visits today, got {visits}")
if "example.com" in visits:
  raise SystemExit("non-LLM hosts were counted")
PY
unset OMARCHY_PARENT_LLM_HOSTS OMARCHY_PARENT_LLM_STATE
pass "History harvest counts today's visits to LLM hosts only"

python3 - "$host" "$tmp" <<'PY'
import json, os, socket, struct, subprocess, sys, threading, time
from pathlib import Path

host = sys.argv[1]
sock_path = str(Path(sys.argv[2]) / "llm.sock")
received = []

def accept():
  server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
  server.bind(sock_path)
  server.listen(1)
  conn, _ = server.accept()
  received.append(conn.recv(65536))
  conn.close()
  server.close()

thread = threading.Thread(target=accept, daemon=True)
thread.start()
time.sleep(0.05)
payload = json.dumps({"prompt": "hello from the extension", "host": "chatgpt.com", "url": "https://chatgpt.com/"}).encode()
stdin = struct.pack("<I", len(payload)) + payload
env = os.environ.copy()
env["OMARCHY_PARENT_LLM_SOCKET"] = sock_path
proc = subprocess.run([host], input=stdin, capture_output=True, env=env)
thread.join(timeout=2)
if proc.returncode != 0:
  raise SystemExit(f"host exited {proc.returncode}: {proc.stderr!r}")
if len(proc.stdout) < 4:
  raise SystemExit("host wrote no native reply")
if not received:
  raise SystemExit("collector socket received nothing")
body = json.loads(received[0].decode().strip())
if body.get("prompt") != "hello from the extension":
  raise SystemExit(f"forwarded payload was {body}")
PY
pass "the native messaging host forwards a prompt to the unix socket"

kid_home="$tmp/kid-home"
mkdir -p "$kid_home/.config"
stub_bin="$tmp/stub-bin"
mkdir -p "$stub_bin" "$tmp/policy" "$tmp/native" "$tmp/systemd" "$tmp/lib" "$tmp/root-reports"
export CALLS="$tmp/systemctl-calls"
: >"$CALLS"

cat >"$stub_bin/omarchy-profile-child" <<'SH'
#!/bin/bash
[[ ${STUB_PROFILE:-child} == child ]]
SH
cat >"$stub_bin/getent" <<'SH'
#!/bin/bash
[[ $2 == kid ]] || exit 1
printf 'kid:x:1000:1000::%s:/bin/bash\n' "$KID_HOME"
SH
cat >"$stub_bin/systemctl" <<'SH'
#!/bin/bash
printf 'systemctl %s\n' "$*" >>"$CALLS"
SH
chmod +x "$stub_bin"/*

run_llm() {
  KID_HOME="$kid_home" \
  OMARCHY_PATH="$ROOT" \
  OMARCHY_PARENT_CONF="$tmp/parent.conf" \
  OMARCHY_PARENT_LIB="$tmp/lib" \
  OMARCHY_PARENT_REPORT_DIR="$tmp/root-reports" \
  OMARCHY_SYSTEMD_DIR="$tmp/systemd" \
  OMARCHY_BROWSER_POLICY_MANAGED_DIRS="$tmp/policy" \
  OMARCHY_NATIVE_MESSAGING_DIRS="$tmp/native" \
  OMARCHY_PARENT_LLM_UNPRIVILEGED=1 \
  PATH="$stub_bin:$PATH" \
  bash "$llm" "$@"
}

if STUB_PROFILE=default run_llm on --user kid >/dev/null 2>&1; then
  fail "on refuses outside the child profile"
fi
pass "on refuses outside the child profile"

run_llm on --user kid >/dev/null || fail "on succeeds on a child install"
[[ -f $tmp/policy/llm.json ]] || fail "on writes the managed policy"
grep -q 'IncognitoModeAvailability' "$tmp/policy/llm.json" || fail "the policy disables incognito"
[[ -f $tmp/native/com.omarchy.parent_llm.json ]] || fail "on writes the system native messaging host"
grep -q "$ROOT/bin/omarchy-parent-llm-host" "$tmp/native/com.omarchy.parent_llm.json" ||
  fail "the native host names the packaged binary"
[[ -f $tmp/systemd/omarchy-parent-llm.socket ]] || fail "on installs the socket unit"
[[ -f $tmp/systemd/omarchy-parent-llm@.service ]] || fail "on installs the connection unit"
[[ -f $tmp/lib/kid/llm/journal.jsonl ]] || fail "on creates the journal"
[[ -f $tmp/lib/kid/llm/hosts.txt ]] || fail "on copies the host list into the feature state"
[[ -d $tmp/root-reports ]] || fail "on creates the report directory"
grep -qx 'llm=on' "$tmp/parent.conf" || fail "on records llm=on in parent.conf"
grep -Fq "$ROOT/default/chromium/extensions/llm-monitor" "$kid_home/.config/chromium-flags.conf" ||
  fail "on loads the extension from the kid's chromium flags"
grep -Fq "copy-url" "$kid_home/.config/chromium-flags.conf" ||
  fail "on keeps the shipped chromium extensions"
[[ ! -f $kid_home/.config/chromium/NativeMessagingHosts/com.omarchy.parent_llm.json ]] ||
  fail "on must not write the native host under the kid home"
pass "on installs policy, the system native host, units, and the journal"

run_llm on --user kid >/dev/null || fail "a rerun of on succeeds"
pass "on is idempotent"

run_llm off --user kid >/dev/null || fail "off succeeds"
[[ ! -f $tmp/policy/llm.json ]] || fail "off removes llm.json"
[[ ! -f $tmp/native/com.omarchy.parent_llm.json ]] || fail "off removes the native host"
[[ ! -f $tmp/systemd/omarchy-parent-llm.socket ]] || fail "off removes the socket unit"
[[ -f $tmp/lib/kid/llm/journal.jsonl ]] || fail "off without --purge keeps the journal"
[[ -d $tmp/root-reports ]] || fail "off without --purge keeps the report directory"
grep -qx 'llm=off' "$tmp/parent.conf" || fail "off records llm=off"
if grep -Fq "$ROOT/default/chromium/extensions/llm-monitor" "$kid_home/.config/chromium-flags.conf" 2>/dev/null; then
  fail "off removes the extension from chromium flags"
fi
grep -Fq "copy-url" "$kid_home/.config/chromium-flags.conf" ||
  fail "off leaves the shipped chromium extensions"
pass "off removes collectors and keeps the journal"

: >"$tmp/lib/kid/llm/journal.jsonl"
run_llm on --user kid >/dev/null || fail "on after off succeeds"
run_llm off --purge --user kid >/dev/null || fail "off --purge succeeds"
[[ ! -e $tmp/lib/kid/llm ]] || fail "off --purge deletes the feature state"
[[ ! -e $tmp/root-reports ]] || fail "off --purge deletes the reports"
pass "off --purge deletes the journal and reports"
