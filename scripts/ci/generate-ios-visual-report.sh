#!/usr/bin/env bash
set -euo pipefail

XC_RESULT="${1:-TestResults.xcresult}"
ATTACHMENTS_DIR="${2:-test-attachments}"
RUN_ID="${GITHUB_RUN_ID:-local}"
SERVER_URL="${GITHUB_SERVER_URL:-https://github.com}"
REPOSITORY="${GITHUB_REPOSITORY:-}"

if [ ! -d "$XC_RESULT" ]; then
  echo "No xcresult bundle at ${XC_RESULT}; skipping visual report."
  exit 0
fi

python3 - "$XC_RESULT" "$ATTACHMENTS_DIR" "$RUN_ID" "$SERVER_URL" "$REPOSITORY" <<'PY'
import base64
import html
import json
import re
import subprocess
import sys
import tempfile
from datetime import datetime
from pathlib import Path

xcresult, attachments_dir, run_id, server_url, repository = sys.argv[1:6]
attachments_path = Path(attachments_dir)
report_path = attachments_path / "report.html"

raw = subprocess.check_output(
    ["xcrun", "xcresulttool", "get", "test-results", "tests", "--path", xcresult, "--format", "json"],
    text=True,
)
data = json.loads(raw)

def walk_nodes(nodes, out):
    if not nodes:
        return
    for node in nodes:
        if (node.get("nodeType") or "") == "Test Case":
            out.append(node)
        walk_nodes(node.get("children") or [], out)

tests = []
walk_nodes(data.get("testNodes") or [], tests)

def failure_message(node):
    for child in node.get("children") or []:
        if (child.get("nodeType") or "") == "Failure Message":
            return str(child.get("name") or "").strip()
    return ""

def safe_name(test_key):
    return re.sub(r"[^\w.-]+", "_", test_key.replace("()", "")).strip("_")

def encode_image(png_path):
    with tempfile.NamedTemporaryFile(suffix=".jpg", delete=False) as tmp:
        thumb_path = Path(tmp.name)
    try:
        subprocess.run(
            [
                "sips", "-Z", "900", "-s", "format", "jpeg", "-s", "formatOptions", "70",
                str(png_path), "--out", str(thumb_path),
            ],
            check=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        encoded = base64.b64encode(thumb_path.read_bytes()).decode("ascii")
        return f"data:image/jpeg;base64,{encoded}"
    except (subprocess.CalledProcessError, OSError):
        encoded = base64.b64encode(png_path.read_bytes()).decode("ascii")
        return f"data:image/png;base64,{encoded}"
    finally:
        thumb_path.unlink(missing_ok=True)

run_url = ""
if run_id != "local" and repository:
    run_url = f"{server_url.rstrip('/')}/{repository}/actions/runs/{run_id}"

passed = failed = 0
sections = []

for test in tests:
    name = test.get("name") or "Unknown"
    file_key = test.get("nodeIdentifier") or name
    result = str(test.get("result") or "")
    if "Pass" in result:
        passed += 1
        continue
    if "Fail" not in result:
        continue
    failed += 1
    msg = failure_message(test)
    png = attachments_path / f"{safe_name(file_key)}.png"
    img_html = ""
    if png.is_file():
        src = encode_image(png)
        img_html = f'<img alt="{html.escape(name)}" src="{src}" />'
    else:
        img_html = '<p class="missing">No failure screenshot exported for this test.</p>'
    sections.append(
        f"""<section class="failure">
  <h2>{html.escape(name)}</h2>
  <p class="meta">Result: {html.escape(result)}</p>
  <pre class="message">{html.escape(msg) if msg else "No failure message captured."}</pre>
  {img_html}
</section>"""
    )

now = datetime.utcnow().strftime("%Y-%m-%d %H:%M UTC")
artifact_note = ""
if run_url:
    artifact_note = f'<p>Workflow run: <a href="{html.escape(run_url)}">{html.escape(run_url)}</a></p>'

document = f"""<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>iOS UI regression report — run {html.escape(run_id)}</title>
  <style>
    body {{ font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; margin: 24px; background: #0f1115; color: #e8eaed; }}
    h1 {{ margin-bottom: 8px; }}
    .summary {{ color: #9aa0a6; margin-bottom: 24px; }}
    .failure {{ background: #1a1d24; border: 1px solid #2d323c; border-radius: 12px; padding: 16px; margin-bottom: 20px; }}
    .failure h2 {{ margin-top: 0; font-size: 1.1rem; }}
    .meta {{ color: #9aa0a6; }}
    pre.message {{ white-space: pre-wrap; background: #11141a; padding: 12px; border-radius: 8px; overflow-x: auto; }}
    img {{ max-width: 100%; height: auto; border-radius: 12px; border: 1px solid #2d323c; margin-top: 12px; }}
    .missing {{ color: #f28b82; }}
    a {{ color: #8ab4f8; }}
  </style>
</head>
<body>
  <h1>iOS UI regression failures</h1>
  <p class="summary">Run <code>{html.escape(run_id)}</code> · {now} · {passed} passed · {failed} failed</p>
  {artifact_note}
  {''.join(sections) if sections else '<p>All tests passed — no failure screenshots.</p>'}
</body>
</html>
"""

attachments_path.mkdir(parents=True, exist_ok=True)
report_path.write_text(document, encoding="utf-8")
print(f"Wrote visual report to {report_path} ({failed} failures).")
PY
