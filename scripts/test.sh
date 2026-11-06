#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/module-cache .build/clang-cache .build/checks
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache"
swiftc -D MESA_MOUSE_SELF_CHECK -parse-as-library \
    -module-cache-path "$PWD/.build/module-cache" \
    Sources/MouseKit/SwipeState.swift Sources/MouseKit/ButtonGestures.swift Tests/MouseKitTests/MouseKitTests.swift \
    -o .build/checks/mouse
.build/checks/mouse
plutil -lint Resources/Info.plist Resources/*.lproj/*.strings
# Every L("…") key must be translated; keys are the English source text.
missing=$(perl -ne 'while (/\bL\("((?:[^"\\]|\\.)*)"/g) { print "$1\n" }' Sources/*/*.swift | sort -u | while IFS= read -r key; do
    for lang in pt-BR es; do grep -qF "\"$key\" =" "Resources/$lang.lproj/Localizable.strings" || echo "$lang: $key"; done
done)
if [ -n "$missing" ]; then printf 'Missing translations:\n%s\n' "$missing"; exit 1; fi
echo "Translations: pt-BR and es cover every key"
git diff --check
