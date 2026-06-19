#!/usr/bin/env bash
set -euo pipefail

XC_RESULT="${1:-TestResults.xcresult}"
OUTPUT_DIR="${2:-test-attachments}"

if [ ! -d "$XC_RESULT" ]; then
  echo "No xcresult bundle at ${XC_RESULT}; skipping screenshot export."
  exit 0
fi

RAW_DIR="${OUTPUT_DIR}/raw"
rm -rf "$OUTPUT_DIR"
mkdir -p "$RAW_DIR"

xcrun xcresulttool export attachments \
  --path "$XC_RESULT" \
  --output-path "$RAW_DIR"

python3 - "$RAW_DIR" "$OUTPUT_DIR" <<'PY'
import json
import re
import shutil
import sys
from pathlib import Path

raw_dir = Path(sys.argv[1])
output_dir = Path(sys.argv[2])
manifest_path = raw_dir / "manifest.json"

if not manifest_path.is_file():
    print("No attachment manifest found; skipping screenshot export.")
    sys.exit(0)

manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
exported = 0

for entry in manifest:
    test_id = entry.get("testIdentifier") or "unknown"
    safe_name = re.sub(r"[^\w.-]+", "_", test_id.replace("()", "")).strip("_")
    attachments = entry.get("attachments") or []

    failure_png = None
    for attachment in attachments:
        name = attachment.get("suggestedHumanReadableName") or ""
        if "Failure screenshot" not in name:
            continue
        file_name = attachment.get("exportedFileName") or ""
        src = raw_dir / file_name
        if src.is_file():
            failure_png = src
            break

    if failure_png is None:
        for attachment in attachments:
            name = attachment.get("suggestedHumanReadableName") or ""
            if "UI Snapshot" not in name and not name.endswith(".png"):
                continue
            file_name = attachment.get("exportedFileName") or ""
            src = raw_dir / file_name
            if src.is_file() and src.suffix.lower() in {".png", ".jpg", ".jpeg"}:
                failure_png = src
                break

    if failure_png is None:
        continue

    dest = output_dir / f"{safe_name}.png"
    shutil.copy2(failure_png, dest)
    exported += 1

shutil.rmtree(raw_dir, ignore_errors=True)
print(f"Exported {exported} failure screenshot(s) to {output_dir}.")
PY
