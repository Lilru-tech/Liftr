#!/usr/bin/env bash
set -euo pipefail

ASSETS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../assets/market/rarity_upgrades" && pwd)"
THRESHOLD="${THRESHOLD:-245}"

python3 <<PY
from PIL import Image
from pathlib import Path

assets = Path("${ASSETS_DIR}")
threshold = int("${THRESHOLD}")

for src in sorted(assets.glob("rarity_upgrade_*.png")):
    img = Image.open(src).convert("RGBA")
    pixels = img.load()
    w, h = img.size
    for y in range(h):
        for x in range(w):
            r, g, b, a = pixels[x, y]
            if r >= threshold and g >= threshold and b >= threshold:
                pixels[x, y] = (r, g, b, 0)
    img.save(src, format="PNG")
    print(f"processed {src.name}")
PY

echo "Done. Re-upload with: supabase storage cp --experimental --linked -r ${ASSETS_DIR} ss:///pets/market/"
