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

MARKET_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../assets/market" && pwd)"
ENERGY_CAPACITY="${MARKET_DIR}/energy_capacity.png"
if [[ -f "$ENERGY_CAPACITY" ]]; then
  python3 <<PY
from PIL import Image
from pathlib import Path

src = Path("${ENERGY_CAPACITY}")
threshold = int("${THRESHOLD}")
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
  echo "Re-upload energy capacity with: supabase storage cp --experimental --linked ${ENERGY_CAPACITY} ss:///pets/market/energy_capacity.png"
fi
