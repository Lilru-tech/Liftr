#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
XC_RESULT="${1:-TestResults.xcresult}"
ATTACHMENTS_DIR="${2:-test-attachments}"
SUMMARY_FILE="${GITHUB_STEP_SUMMARY:-/dev/stdout}"
RUN_ID="${GITHUB_RUN_ID:-local}"
SERVER_URL="${GITHUB_SERVER_URL:-https://github.com}"
REPOSITORY="${GITHUB_REPOSITORY:-}"

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

python3 - "$XC_RESULT" "$SUMMARY_FILE" "$RUN_ID" "$BRANCH_URL" "$ATTACHMENTS_DIR" "$SERVER_URL" "$REPOSITORY" <<'PY'
import base64
import json
import re
import subprocess
import sys
import tempfile
from datetime import datetime
from pathlib import Path

xcresult, summary_path, run_id, branch_url, attachments_dir, server_url, repository = sys.argv[1:8]
attachments_path = Path(attachments_dir)

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
    for child in node.get("children") or []:
        if (child.get("nodeType") or "") == "Failure Message":
            name = child.get("name")
            if name:
                return str(name).strip()
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
    for child in node.get("children") or []:
        node_type = child.get("nodeType") or ""
        if node_type in ("Activity", "Test Activity"):
            title = child.get("name") or child.get("title")
            if title:
                steps.append(str(title))
    return steps

def safe_test_file_name(test_name):
    return re.sub(r"[^\w.-]+", "_", test_name.replace("()", "")).strip("_")

def run_url():
    if run_id == "local" or not repository:
        return ""
    return f"{server_url.rstrip('/')}/{repository}/actions/runs/{run_id}"

def artifacts_url():
    url = run_url()
    return f"{url}#artifacts" if url else ""

def artifact_link():
    url = artifacts_url()
    if not url:
        return "see test-attachments artifact"
    return f"[download screenshots]({url})"

def thumbnail_img_tag(png_path):
    with tempfile.NamedTemporaryFile(suffix=".jpg", delete=False) as tmp:
        thumb_path = Path(tmp.name)
    try:
        subprocess.run(
            [
                "sips",
                "-Z",
                "320",
                "-s",
                "format",
                "jpeg",
                "-s",
                "formatOptions",
                "55",
                str(png_path),
                "--out",
                str(thumb_path),
            ],
            check=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        encoded = base64.b64encode(thumb_path.read_bytes()).decode("ascii")
        return f'<img alt="failure screenshot" src="data:image/jpeg;base64,{encoded}" width="220" />'
    except (subprocess.CalledProcessError, OSError):
        return ""
    finally:
        thumb_path.unlink(missing_ok=True)

def screenshot_cell(test_name, failed):
    if not failed:
        return "—"
    safe_name = safe_test_file_name(test_name)
    png_path = attachments_path / f"{safe_name}.png"
    link = artifact_link()
    if png_path.is_file():
        img = thumbnail_img_tag(png_path)
        if img:
            return f"{img}<br>{link}"
    return link

passed = failed = skipped = 0
rows = []
failed_details = []

for t in tests:
    name = t.get("name") or t.get("identifier") or t.get("nodeIdentifier") or "Unknown test"
    file_key = t.get("nodeIdentifier") or name
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

    is_failed = "fail" in normalized or "error" in normalized
    step_text = "<br>".join(steps) if steps else "—"
    screenshot = screenshot_cell(file_key, is_failed)

    detail = step_text
    if is_failed and msg:
        detail = step_text + "<br><br>**Failure:** " + msg.replace("\n", "<br>")

    rows.append((name, result, f"{dur:.1f}s", detail, screenshot))

    if is_failed:
        failed_details.append((name, msg, steps, file_key))

total = len(rows)
now = datetime.utcnow().strftime("%Y-%m-%d %H:%M UTC")
run_link = run_url()

lines = [
    "## iOS UI regression results",
    "",
    f"Run `{run_id}` · {now} · {passed}/{total} passed",
]
if run_link:
    lines.append(f"Workflow run: [{run_link}]({run_link})")
if branch_url:
    lines.append(f"Supabase branch: `{branch_url}`")
lines.extend(["", "| Test | Result | Duration | Steps / failure | Screenshot |", "| --- | --- | --- | --- | --- |"])

for name, result, dur, detail, shot in rows:
    safe_name = name.replace("|", "\\|")
    safe_detail = detail.replace("|", "\\|") if detail else "—"
    lines.append(f"| `{safe_name}` | {result} | {dur} | {safe_detail} | {shot} |")

if failed_details:
    lines.extend(["", "### Failed tests", ""])
    for name, msg, steps, file_key in failed_details:
        lines.append(f"#### `{name}`")
        if steps:
            lines.append("")
            lines.append("**Steps:**")
            for s in steps:
                lines.append(f"- {s}")
        if msg:
            lines.append("")
            lines.append("**Failure:**")
            lines.append("```")
            lines.append(msg)
            lines.append("```")
        safe_name = safe_test_file_name(file_key)
        png_path = attachments_path / f"{safe_name}.png"
        if png_path.is_file():
            img = thumbnail_img_tag(png_path)
            if img:
                lines.append("")
                lines.append(img)
        lines.append("")

if run_id != "local" and repository:
    lines.extend([
        "",
        f"Full-resolution failure screenshots: download artifact **`ios-ui-screenshots-{run_id}`** from [this workflow run]({artifacts_url()}).",
    ])

content = "\n".join(lines) + "\n"

with open(summary_path, "a", encoding="utf-8") as fh:
    fh.write(content)

print(f"Wrote summary for {total} tests ({passed} passed, {failed} failed, {skipped} skipped).")
PY
