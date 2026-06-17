#!/usr/bin/env bash
set -euo pipefail

preferred_names=(
  "iPhone 17 Pro Max"
  "iPhone 16 Pro Max"
  "iPhone 16 Pro"
  "iPhone 15 Pro"
)

available_devices="$(xcrun simctl list devices available)"

for name in "${preferred_names[@]}"; do
  if echo "$available_devices" | grep -F "$name (" >/dev/null 2>&1; then
    echo "name=\"${name}\""
    exit 0
  fi
done

fallback_name="$(echo "$available_devices" | sed -n 's/^[[:space:]]*\(iPhone[^()]*\) (.*/\1/p' | head -n 1)"
if [ -z "$fallback_name" ]; then
  echo "No available iPhone simulators found"
  exit 1
fi

echo "name=\"${fallback_name}\""
