#!/usr/bin/env bash
# Copies keybee's published grant vectors into the test resources and records
# the keybee commit they came from.
# Usage: scripts/sync-vectors.sh <path to a keybee checkout>
set -euo pipefail
src="${1:?usage: scripts/sync-vectors.sh <path to a keybee checkout>}"
dest="$(cd "$(dirname "$0")/.." && pwd)/Tests/KeybeeTests/Resources"
mkdir -p "$dest"
cp "$src/openapi/vectors/grants.json" "$src/openapi/vectors/jwk.json" "$dest/"
git -C "$src" rev-parse HEAD > "$dest/VECTORS_SOURCE"
echo "copied $(python3 -c 'import json,sys; print(len(json.load(open(sys.argv[1]))))' "$dest/grants.json") vectors from $(cat "$dest/VECTORS_SOURCE")"
