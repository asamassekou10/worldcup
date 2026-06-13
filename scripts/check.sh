#!/usr/bin/env bash
# Full local verification: format, lint, and TYPE-CHECK (the last one catches
# Vector3/CFrame mix-ups, nil casts, etc. that format+lint+build miss).
# Run from anywhere: ./scripts/check.sh
set -euo pipefail

cd "$(dirname "$0")/.."
export PATH="$HOME/.rokit/bin:$PATH"

echo "== stylua (format) =="
stylua --check src/

echo "== selene (lint) =="
selene src/

# Roblox API type definitions for luau-lsp (generated, gitignored).
if [ ! -f globalTypes.d.luau ]; then
	echo "== fetching Roblox type definitions =="
	curl -fsSL -o globalTypes.d.luau \
		"https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/main/scripts/globalTypes.d.luau"
fi

echo "== sourcemap =="
rojo sourcemap default.project.json -o sourcemap.json --include-non-scripts >/dev/null

echo "== luau-lsp (type-check) =="
luau-lsp analyze \
	--sourcemap=sourcemap.json \
	--definitions=globalTypes.d.luau \
	--platform=roblox \
	--ignore="**/ProfileStore.luau" \
	--ignore="Packages/**" \
	src

echo "All checks passed ✅"
