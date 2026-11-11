#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
build_root="${TMPDIR:-/tmp}/horizonmouse-local-build"
mkdir -p "$build_root/module-cache" "$build_root/clang-cache" "$build_root/cache" dist
export CLANG_MODULE_CACHE_PATH="$build_root/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$build_root/module-cache"
# shortcut: use a local temporary build database; reevaluate after the Swift 6.4 cache issue is fixed.
swift build --build-system native --disable-sandbox --scratch-path "$build_root/build" --cache-path "$build_root/cache" -c release --arch arm64 --arch x86_64
binary_dir=$(swift build --build-system native --disable-sandbox --scratch-path "$build_root/build" --cache-path "$build_root/cache" -c release --arch arm64 --arch x86_64 --show-bin-path)
staging=$(mktemp -d "$build_root/package.XXXXXX")
trap 'rm -rf "$staging"' EXIT
app="$staging/Horizon Mouse.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$binary_dir/HorizonMouse" "$app/Contents/MacOS/HorizonMouse"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp -R Resources/*.lproj "$app/Contents/Resources/"
cp LICENSE Resources/AppIcon.icns Resources/KofiCup.png "$app/Contents/Resources/"
# A stable certificate keeps the Accessibility grant across updates (it is tied to the certificate, not the build).
# Ad-hoc ("-") works too, but every build then needs a new grant. See CONTRIBUTING.md.
identity="${HORIZON_SIGN_IDENTITY:-Mac Mouse Desk Self-Signed}"
security find-certificate -c "$identity" >/dev/null 2>&1 || { echo "Certificado \"$identity\" ausente: assinatura ad-hoc." >&2; identity=-; }
codesign --force --sign "$identity" --identifier io.github.luishscosta.horizonmouse "$app"
codesign --verify --strict "$app"
ditto -c -k --norsrc --keepParent "$app" "$PWD/dist/HorizonMouse.zip"
# Drag-to-install disk image: the app next to an Applications shortcut.
dmg_root="$staging/dmg"
mkdir -p "$dmg_root"
ditto --norsrc "$app" "$dmg_root/Horizon Mouse.app"
ln -s /Applications "$dmg_root/Applications"
rm -f "$PWD/dist/HorizonMouse.dmg"
hdiutil create -quiet -volname "Horizon Mouse" -srcfolder "$dmg_root" -fs HFS+ -format UDZO "$PWD/dist/HorizonMouse.dmg"
codesign --force --sign "$identity" "$PWD/dist/HorizonMouse.dmg"
(cd "$PWD/dist" && shasum -a 256 HorizonMouse.zip HorizonMouse.dmg > SHA256SUMS.txt)
rm -rf "$build_root/Horizon Mouse.app"
ditto --norsrc "$app" "$build_root/Horizon Mouse.app"
codesign --verify --strict "$build_root/Horizon Mouse.app"
printf 'Aplicativo compilado: %s\nPacotes: %s, %s\n' "$build_root/Horizon Mouse.app" "$PWD/dist/HorizonMouse.zip" "$PWD/dist/HorizonMouse.dmg"
