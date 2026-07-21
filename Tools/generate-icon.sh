#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
asset_dir="$project_dir/Assets"
iconset_dir="$asset_dir/AppIcon.iconset"
source_png="$asset_dir/AppIcon-1024.png"

mkdir -p "$asset_dir" "$iconset_dir"
swift "$project_dir/Tools/generate-icon.swift" "$source_png"
sips -z 1024 1024 "$source_png" --out "$source_png" >/dev/null

for spec in \
    "16 icon_16x16.png" \
    "32 icon_16x16@2x.png" \
    "32 icon_32x32.png" \
    "64 icon_32x32@2x.png" \
    "128 icon_128x128.png" \
    "256 icon_128x128@2x.png" \
    "256 icon_256x256.png" \
    "512 icon_256x256@2x.png" \
    "512 icon_512x512.png" \
    "1024 icon_512x512@2x.png"
do
    dimension="${spec%% *}"
    filename="${spec#* }"
    sips -z "$dimension" "$dimension" "$source_png" --out "$iconset_dir/$filename" >/dev/null
done

iconutil -c icns "$iconset_dir" -o "$asset_dir/AppIcon.icns"
rm -r "$iconset_dir"
