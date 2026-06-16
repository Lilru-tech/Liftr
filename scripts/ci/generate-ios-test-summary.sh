#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
XC_RESULT="${1:-TestResults.xcresult}"
SUMMARY_FILE="${GITHUB_STEP_SUMMARY:-/dev/stdout}"

if [ ! -d "$XC_RESULT" ]; then
  echo "No xcresult bundle at ${XC_RESULT}; skipping summary."
  exit 0
fi

BRANCH_ENV="${ROOT_DIR}/scripts/ci/.branch.env"
BRANCH_URL=""
if [ -f "$BRANCH_ENV" ]; then
  # shellcheck disable=SC1090
  source "$BRANCH_ENV"
  if [ -n "${SUPABASE_URL:-}" ]; then
    BRANCH_URL="$SUPABASE_URL"
  fi
fi

python3 - "$XC_RESULT" "$SUMMARY_FILE" "${GITHUB_RUN_ID:-local}" "$BRANCH_URL" <<'PY'
import json
import subprocess
import sys
from datetime import datetime

xcresult, summary_path, run_id, branch_url = sys.argv[1:5]

raw = subprocess.check_output(
    ["xcrun", "xcresulttool", "get", "test-results", "tests", "--path", xcresult, "--format", "json"],
    text=True,
)

data = json.loads(raw)

def walk_nodes(nodes, out):
    if not nodes:
        return
    for node in nodes:
        node_type = node.get("nodeType") or node.get("type") or ""
        if node_type in ("Test Case", "TestCase"):
            out.append(node)
        children = node.get("children") or node.get("testNodes") or []
        walk_nodes(children, out)

tests = []
top = data.get("testNodes") or data.get("tests") or []
if isinstance(top, dict):
    top = top.get("children") or top.get("testNodes") or []
walk_nodes(top if isinstance(top, list) else [top], tests)

if not tests and isinstance(data, list):
    walk_nodes(data, tests)

def status_label(node):
    for key in ("result", "status", "testStatus"):
        val = node.get(key)
        if val:
            return str(val)
    return "Unknown"

def duration_seconds(node):
    for key in ("durationInSeconds", "duration", "durationSec"):
        val = node.get(key)
        if val is not None:
            try:
                return float(val)
            except (TypeError, ValueError):
                pass
    return 0.0

def failure_message(node):
    for key in ("failureMessage", "failureSummary", "message"):
        val = node.get(key)
        if val:
            return str(val).strip()
    failures = node.get("failures") or []
    if failures:
        parts = []
        for f in failures:
            if isinstance(f, dict):
                msg = f.get("failureMessage") or f.get("message") or f.get("description")
                if msg:
                    parts.append(str(msg).strip())
            elif f:
                parts.append(str(f).strip())
        if parts:
            return "\n".join(parts)
    return ""

def activity_steps(node):
    steps = []
    for key in ("activities", "activitySummaries", "subactivities"):
        acts = node.get(key) or []
        for act in acts:
            if isinstance(act, dict):
                title = act.get("title") or act.get("name")
                if title:
                    steps.append(str(title))
            elif act:
                steps.append(str(act))
    return steps

passed = failed = skipped = 0
rows = []
failed_details = []

for t in tests:
    name = t.get("name") or t.get("identifier") or "Unknown test"
    status = status_label(t)
    dur = duration_seconds(t)
    msg = failure_message(t)
    steps = activity_steps(t)

    normalized = status.lower()
    if "pass" in normalized or normalized == "succeeded":
        passed += 1
        result = "✅ Pass"
    elif "skip" in normalized:
        skipped += 1
        result = "⏭ Skip"
    elif "fail" in normalized or "error" in normalized:
        failed += 1
        result = "❌ Fail"
    else:
        result = status

    step_text = "<br>".join(steps) if steps else "—"
    screenshot = "—"
    if "fail" in normalized or "error" in normalized:
        screenshot = f"[artifact `ios-ui-screenshots-{run_id}`](https://github.com/actions/runs/{run_id})" if run_id != "local" else "see test-attachments artifact"

    detail = step_text
    if ("fail" in normalized or "error" in normalized) and msg:
        detail = step_text + "<br>" + msg.replace("\n", "<br>")

    rows.append((name, result, f"{dur:.1f}s", detail, screenshot))

    if "fail" in normalized or "error" in normalized:
        failed_details.append((name, msg, steps))

total = len(rows)
now = datetime.utcnow().strftime("%Y-%m-%d %H:%M UTC")

lines = [
    f"## iOS UI regression results",
    "",
    f"Run `{run_id}` · {now} · {passed}/{total} passed",
]
if branch_url:
    lines.append(f"Supabase branch: `{branch_url}`")
lines.extend(["", "| Test | Result | Duration | Steps / failure | Screenshot |", "| --- | --- | --- | --- | --- |"])

for name, result, dur, detail, shot in rows:
    safe_name = name.replace("|", "\\|")
    safe_detail = detail.replace("|", "\\|") if detail else "—"
    lines.append(f"| `{safe_name}` | {result} | {dur} | {safe_detail} | {shot} |")

if failed_details:
    lines.extend(["", "### Failed tests", ""])
    for name, msg, steps in failed_details:
        lines.append(f"#### `{name}`")
        if steps:
            lines.append("")
            lines.append("**Steps:**")
            for s in steps:
                lines.append(f"- {s}")
        if msg:
            lines.append("")
            lines.append("**Failure:**")
            lines.append(f"```")
            lines.append(msg)
            lines.append(f"```")
        lines.append("")

if run_id != "local":
    lines.extend([
        "",
        f"Failure screenshots: download artifact **`ios-ui-screenshots-{run_id}`** from this workflow run.",
    ])

content = "\n".join(lines) + "\n"

with open(summary_path, "a", encoding="utf-8") as fh:
    fh.write(content)

print(f"Wrote summary for {total} tests ({passed} passed, {failed} failed, {skipped} skipped).")
PY
