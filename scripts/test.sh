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
    for lang in $(cd Resources && ls -d *.lproj | sed "s/.lproj//"); do grep -qF "\"$key\" =" "Resources/$lang.lproj/Localizable.strings" || echo "$lang: $key"; done
done)
if [ -n "$missing" ]; then printf 'Missing translations:\n%s\n' "$missing"; exit 1; fi
echo "Translations: every language covers every key"
# The release workflow derives the next version from commit messages.
check_version() { got=$(printf '%s\n' "$2" | bash scripts/next-version.sh "$1"); [ "$got" = "$3" ] || { echo "next-version: expected '$3', got '$got' for: $2"; exit 1; }; }
check_version 0.3.9 "feat: x" 0.4.0
check_version 0.3.9 $'fix: a\nfeat(ui): b' 0.4.0
check_version 0.3.9 "fix: a" 0.3.10
check_version 0.3.9 "docs: a" ""
check_version 0.3.9 "feat!: a" 1.0.0
check_version 0.3.9 $'chore: x\n\nBREAKING CHANGE: y' 1.0.0
echo "Release versions: commit messages map to the right bump"
git diff --check
