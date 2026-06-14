#!/usr/bin/env bash
set -euo pipefail

SOURCE_PETS_BASE="${SOURCE_PETS_BASE:-https://grwdnzjqrqayhmmhxocu.supabase.co/storage/v1/object/public/pets}"
SOURCE_MARKET_BASE="${SOURCE_MARKET_BASE:-https://grwdnzjqrqayhmmhxocu.supabase.co/storage/v1/object/public/market}"
LIFTR_SUPABASE_URL="${LIFTR_SUPABASE_URL:-https://rjzhaafvkxmvlnpsikbi.supabase.co}"
BUCKET="${BUCKET:-pets}"
TMP_DIR="${TMP_DIR:-/tmp/liftr-pet-assets}"

if [[ -z "${SUPABASE_SERVICE_ROLE_KEY:-}" ]]; then
  echo "Set SUPABASE_SERVICE_ROLE_KEY to upload into Liftr Supabase Storage."
  exit 1
fi

mkdir -p "$TMP_DIR"

PET_TYPES=(
  dragon unicorn phoenix tiger lion wolf monkey raccoon fox turtle panda chick bunny
  octopus dolphin tiranosaurus triceratops pterodactyl shark orca crocodile owl flamingo
  snake lynx griffin elephant leopard gorilla hippo koala kangaroo armadillo eagle crab
  sphinx chimera ice_phoenix godzilla cybercat mechadragon void_serpent holofox neon_panther
  astrowolf quantum_slime drone_beetle kitsune chocobo celestial_kirin skydasher soul_wisp
  oniricat drakeling mythochic zorgling xenopup starfishoid meteokko shadowbunny grim_pup
  spectrophant cryptocat witch_crow demon hellhound
)

STAGES=(egg baby kid teen adult senior elder)

upload_object() {
  local dest_path="$1"
  local file_path="$2"
  curl -sfS -X POST \
    "${LIFTR_SUPABASE_URL}/storage/v1/object/${BUCKET}/${dest_path}" \
    -H "Authorization: Bearer ${SUPABASE_SERVICE_ROLE_KEY}" \
    -H "Content-Type: image/png" \
    -H "x-upsert: true" \
    --data-binary @"${file_path}" >/dev/null
  echo "uploaded ${dest_path}"
}

mirror_sprite() {
  local name="$1"
  local stage="$2"
  local dest_stage="$2"
  local src="${SOURCE_PETS_BASE}/${name}_${stage}.png"
  local dest_file="${TMP_DIR}/${name}_${dest_stage}.png"
  if ! curl -sfS "$src" -o "$dest_file"; then
    echo "skip missing ${src}"
    return 0
  fi
  upload_object "${name}_${dest_stage}.png" "$dest_file"
  if [[ "$stage" == "senior" ]]; then
    upload_object "${name}_elder.png" "$dest_file"
  fi
}

for pet in "${PET_TYPES[@]}"; do
  for stage in "${STAGES[@]}"; do
    mirror_sprite "$pet" "$stage"
  done
done

declare -A MARKET_ASSETS=(
  [incubator.png]="incubator.png"
  [food_baby.png]="baby_snack.png"
  [food_kid.png]="kid_cookie.png"
  [food_teen.png]="teen_treat.png"
  [food_adult.png]="adult_biscuit.png"
  [food_elder.png]="elder_delight.png"
)

for dest_name in "${!MARKET_ASSETS[@]}"; do
  src_name="${MARKET_ASSETS[$dest_name]}"
  src="${SOURCE_MARKET_BASE}/${src_name}"
  dest_file="${TMP_DIR}/${dest_name}"
  if curl -sfS "$src" -o "$dest_file" 2>/dev/null; then
    upload_object "market/${dest_name}" "$dest_file"
  else
    echo "skip optional market asset ${src}"
  fi
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RARITY_UPGRADE_DIR="${SCRIPT_DIR}/../assets/market/rarity_upgrades"
if [[ -d "$RARITY_UPGRADE_DIR" ]]; then
  for asset in "$RARITY_UPGRADE_DIR"/rarity_upgrade_*.png; do
    [[ -f "$asset" ]] || continue
    upload_object "market/$(basename "$asset")" "$asset"
  done
fi

PET_EGG_ASSET="${SCRIPT_DIR}/../assets/market/pet_egg.png"
if [[ -f "$PET_EGG_ASSET" ]]; then
  upload_object "market/pet_egg.png" "$PET_EGG_ASSET"
fi

ENERGY_CAPACITY_ASSET="${SCRIPT_DIR}/../assets/market/energy_capacity.png"
if [[ -f "$ENERGY_CAPACITY_ASSET" ]]; then
  upload_object "market/energy_capacity.png" "$ENERGY_CAPACITY_ASSET"
fi

echo "Done. Public URL pattern: ${LIFTR_SUPABASE_URL}/storage/v1/object/public/${BUCKET}/{pet_type}_{stage}.png"
