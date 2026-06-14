#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MARKET_DIR="${SCRIPT_DIR}/../assets/market"
SOURCE_PETS_BASE="${SOURCE_PETS_BASE:-https://grwdnzjqrqayhmmhxocu.supabase.co/storage/v1/object/public/pets}"
SOURCE_MARKET_BASE="${SOURCE_MARKET_BASE:-https://grwdnzjqrqayhmmhxocu.supabase.co/storage/v1/object/public/market}"
TOLERANCE="${TOLERANCE:-35}"
DEST="${MARKET_DIR}/pet_egg.png"
TMP_SRC="$(mktemp /tmp/pet_egg_src.XXXXXX.png)"

mkdir -p "$MARKET_DIR"

if [[ -f "$DEST" ]]; then
  SRC="$DEST"
elif curl -sfS "${SOURCE_MARKET_BASE}/egg.png" -o "$TMP_SRC" 2>/dev/null; then
  SRC="$TMP_SRC"
elif curl -sfS "${SOURCE_PETS_BASE}/dragon_egg.png" -o "$TMP_SRC" 2>/dev/null; then
  SRC="$TMP_SRC"
else
  echo "No pet egg source found. Place a source PNG at ${DEST} or ensure SettleIt market assets are reachable."
  exit 1
fi

python3 <<PY
from collections import deque
from PIL import Image

src = "${SRC}"
dest = "${DEST}"
tolerance = int("${TOLERANCE}")

img = Image.open(src).convert("RGBA")
w, h = img.size
px = img.load()
visited = [[False] * w for _ in range(h)]
queue = deque()
for sx, sy in ((0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)):
    if not visited[sy][sx]:
        queue.append((sx, sy))
        visited[sy][sx] = True

bg = px[0, 0][:3]
while queue:
    x, y = queue.popleft()
    r, g, b, a = px[x, y]
    if abs(r - bg[0]) + abs(g - bg[1]) + abs(b - bg[2]) <= tolerance:
        px[x, y] = (r, g, b, 0)
        for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
            if 0 <= nx < w and 0 <= ny < h and not visited[ny][nx]:
                visited[ny][nx] = True
                queue.append((nx, ny))

img.save(dest, format="PNG")
print(f"processed {dest}")
PY

rm -f "$TMP_SRC"
echo "Re-upload with: supabase storage cp --experimental --linked ${DEST} ss:///pets/market/pet_egg.png"
