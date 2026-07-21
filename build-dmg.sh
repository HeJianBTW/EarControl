#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h}"
output_dir="${1:-$project_dir/dist}"
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$project_dir/Info.plist")
dmg_path="$output_dir/EarControl-v${version}-macOS.dmg"
staging_root=$(mktemp -d /tmp/earcontrol-dmg.XXXXXX)
app_output="$staging_root/app"
dmg_root="$staging_root/dmg"

cleanup() {
    if [[ "$staging_root" == /tmp/earcontrol-dmg.* && -d "$staging_root" ]]; then
        rm -rf "$staging_root"
    fi
}
trap cleanup EXIT

mkdir -p "$output_dir" "$dmg_root"
release_signing_identity="${EARCONTROL_SIGNING_IDENTITY:-}"
if [[ -z "$release_signing_identity" ]]; then
    release_signing_identity=$(security find-identity -v -p codesigning 2>/dev/null \
        | sed -n 's/.*"\(Developer ID Application:[^"]*\)".*/\1/p' \
        | head -n 1)
fi
if [[ -z "$release_signing_identity" ]]; then
    release_signing_identity=$(security find-identity -v -p codesigning 2>/dev/null \
        | sed -n 's/.*"\(Apple Development:[^"]*\)".*/\1/p' \
        | head -n 1)
fi
if [[ -z "$release_signing_identity" || "$release_signing_identity" == "-" ]]; then
    print -u2 "error: refusing to build a public DMG without a stable signing identity"
    print -u2 "ad-hoc signed apps can be granted Accessibility access while PostEvent remains denied"
    exit 1
fi
if [[ "$release_signing_identity" == Apple\ Development:* ]]; then
    print -u2 "warning: building an Apple Development-signed test DMG; Gatekeeper override is still required"
fi
EARCONTROL_SIGNING_IDENTITY="$release_signing_identity" "$project_dir/build-app.sh" "$app_output"
ditto "$app_output/EarControl.app" "$dmg_root/EarControl.app"
ln -s /Applications "$dmg_root/Applications"
cp "$project_dir/docs/安装说明.txt" "$dmg_root/安装说明.txt"

hdiutil create \
    -volname "EarControl" \
    -srcfolder "$dmg_root" \
    -format UDZO \
    -ov \
    "$dmg_path"

shasum -a 256 "$dmg_path"
echo "$dmg_path"
