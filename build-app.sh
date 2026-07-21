#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h}"
output_dir="${1:-$project_dir/dist}"
app_dir="$output_dir/EarControl.app"

cd "$project_dir"
swift build -c release

mkdir -p "$app_dir/Contents/MacOS"
mkdir -p "$app_dir/Contents/Resources"
cp .build/release/EarControl "$app_dir/Contents/MacOS/EarControl"
cp Info.plist "$app_dir/Contents/Info.plist"
cp Assets/AppIcon.icns "$app_dir/Contents/Resources/AppIcon.icns"
xattr -cr "$app_dir"
signing_identity="${EARCONTROL_SIGNING_IDENTITY:-}"
if [[ -z "$signing_identity" ]]; then
    signing_identity=$(security find-identity -v -p codesigning 2>/dev/null \
        | sed -n 's/.*"\(Developer ID Application:[^"]*\)".*/\1/p' \
        | head -n 1)
fi
if [[ -z "$signing_identity" ]]; then
    signing_identity=$(security find-identity -v -p codesigning 2>/dev/null \
        | sed -n 's/.*"\(Apple Development:[^"]*\)".*/\1/p' \
        | head -n 1)
fi
if [[ -z "$signing_identity" ]]; then
    signing_identity="-"
    print -u2 "warning: no stable signing identity found; accessibility permission may reset after rebuilding"
fi

print "Signing EarControl with: $signing_identity"
codesign --force --deep --timestamp=none --sign "$signing_identity" "$app_dir"
xattr -cr "$app_dir"
codesign --verify --deep --strict "$app_dir"

echo "$app_dir"
