#!/bin/zsh
set -euo pipefail
project_dir="${0:A:h:h}"
cd "$project_dir"
swift build -c release --product FrameStudio \
    -Xswiftc -debug-prefix-map -Xswiftc "$project_dir=." \
    -Xswiftc -file-prefix-map -Xswiftc "$project_dir=."
mkdir -p .build/AppIcon.iconset
swift scripts/Icon.swift .build/icon.png
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" .build/icon.png --out ".build/AppIcon.iconset/icon_${size}x${size}.png" >/dev/null
    double_size=$((size * 2))
    sips -z "$double_size" "$double_size" .build/icon.png --out ".build/AppIcon.iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil --convert icns .build/AppIcon.iconset --output .build/AppIcon.icns
# Sign outside the cloud-synced workspace, where FileProvider can reattach FinderInfo.
build_root="$(mktemp -d "${TMPDIR:-/tmp}/yingkuang-build.XXXXXX")"
trap 'rm -rf "$build_root"' EXIT
app_dir="$build_root/映框.app"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp .build/release/FrameStudio "$app_dir/Contents/MacOS/FrameStudio"
strip -S "$app_dir/Contents/MacOS/FrameStudio"
cp .build/AppIcon.icns "$app_dir/Contents/Resources/AppIcon.icns"
cp Assets/Sample.jpg "$app_dir/Contents/Resources/Sample.jpg"
cp LICENSE THIRD_PARTY_NOTICES.md PRIVACY.md "$app_dir/Contents/Resources/"
cat > "$app_dir/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>local.wenhanyu.frame-studio</string>
<key>CFBundleName</key><string>映框</string>
<key>CFBundleDisplayName</key><string>映框</string>
<key>CFBundleExecutable</key><string>FrameStudio</string>
<key>CFBundleIconFile</key><string>AppIcon.icns</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.11.2</string>
<key>CFBundleVersion</key><string>27</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>CFBundleDocumentTypes</key><array><dict>
<key>CFBundleTypeName</key><string>照片</string>
<key>CFBundleTypeRole</key><string>Viewer</string>
<key>LSHandlerRank</key><string>Alternate</string>
<key>LSItemContentTypes</key><array><string>public.image</string></array>
</dict></array>
</dict></plist>
PLIST
xattr -cr "$app_dir"
codesign --force --sign - "$app_dir"
codesign --verify --deep --strict "$app_dir"
mkdir -p "$project_dir/dist"
ditto --norsrc --noextattr "$app_dir" "$project_dir/dist/映框.app"
# Mark non-ASCII paths as UTF-8, while preserving Unix executable permissions.
python3 - "$app_dir" "$project_dir/dist/映框.zip" <<'PY'
from pathlib import Path
import sys, zipfile
app = Path(sys.argv[1])
with zipfile.ZipFile(sys.argv[2], 'w', compression=zipfile.ZIP_DEFLATED) as archive:
    for entry in [app, *sorted(app.rglob('*'))]:
        archive.write(entry, entry.relative_to(app.parent))
PY
if [[ "${1:-}" == "--install" ]]; then
    destination="$HOME/Applications/映框.app"
    if [[ -e "$destination" ]]; then
        print -u2 "安装位置已存在，请保留旧版后手动更新：$destination"
        exit 1
    fi
    mkdir -p "$HOME/Applications"
    ditto --norsrc --noextattr "$app_dir" "$destination"
    codesign --verify --deep --strict "$destination"
    print "$destination"
else
    print "$project_dir/dist/映框.app"
fi
