#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
build_root="${TMPDIR:-/tmp}/mesa-local-build"
mkdir -p "$build_root/module-cache" "$build_root/clang-cache" "$build_root/cache" dist
export CLANG_MODULE_CACHE_PATH="$build_root/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$build_root/module-cache"
# shortcut: use a local temporary build database; reevaluate after the Swift 6.4 cache issue is fixed.
swift build --build-system native --disable-sandbox --scratch-path "$build_root/build" --cache-path "$build_root/cache" -c release --arch arm64 --arch x86_64
binary_dir=$(swift build --build-system native --disable-sandbox --scratch-path "$build_root/build" --cache-path "$build_root/cache" -c release --arch arm64 --arch x86_64 --show-bin-path)
staging=$(mktemp -d "$build_root/package.XXXXXX")
trap 'rm -rf "$staging"' EXIT
app="$staging/Mac Mouse Desk.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$binary_dir/Mesa" "$app/Contents/MacOS/Mesa"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp -R Resources/*.lproj "$app/Contents/Resources/"
cp LICENSE Resources/AppIcon.icns "$app/Contents/Resources/"
# A stable certificate keeps the Accessibility grant across updates (it is tied to the certificate, not the build).
# Ad-hoc ("-") works too, but every build then needs a new grant. See CONTRIBUTING.md.
identity="${MMD_SIGN_IDENTITY:-Mac Mouse Desk Self-Signed}"
security find-certificate -c "$identity" >/dev/null 2>&1 || { echo "Certificado \"$identity\" ausente: assinatura ad-hoc." >&2; identity=-; }
codesign --force --sign "$identity" --identifier local.macos-config.Mesa "$app"
codesign --verify --strict "$app"
ditto -c -k --norsrc --keepParent "$app" "$PWD/dist/MacMouseDesk.zip"
# Drag-to-install disk image: the app next to an Applications shortcut.
dmg_root="$staging/dmg"
mkdir -p "$dmg_root"
ditto --norsrc "$app" "$dmg_root/Mac Mouse Desk.app"
ln -s /Applications "$dmg_root/Applications"
rm -f "$PWD/dist/MacMouseDesk.dmg"
hdiutil create -quiet -volname "Mac Mouse Desk" -srcfolder "$dmg_root" -fs HFS+ -format UDZO "$PWD/dist/MacMouseDesk.dmg"
codesign --force --sign "$identity" "$PWD/dist/MacMouseDesk.dmg"
(cd "$PWD/dist" && shasum -a 256 MacMouseDesk.zip MacMouseDesk.dmg > SHA256SUMS.txt)
rm -rf "$build_root/Mac Mouse Desk.app"
ditto --norsrc "$app" "$build_root/Mac Mouse Desk.app"
codesign --verify --strict "$build_root/Mac Mouse Desk.app"
printf 'Aplicativo compilado: %s\nPacotes: %s, %s\n' "$build_root/Mac Mouse Desk.app" "$PWD/dist/MacMouseDesk.zip" "$PWD/dist/MacMouseDesk.dmg"
