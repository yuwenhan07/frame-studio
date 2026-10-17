#!/bin/zsh
set -euo pipefail
project_dir="${0:A:h:h}"
cd "$project_dir"
check_dir="$project_dir/.build/selection-checks"
mkdir -p "$check_dir"
task_arch="$(uname -m)"
xcrun swiftc -swift-version 5 -O -target "$task_arch-apple-macos14.0" -parse-as-library \
    -emit-module -emit-library -module-name FrameCore \
    -emit-module-path "$check_dir/FrameCore.swiftmodule" \
    Sources/FrameCore/*.swift -o "$check_dir/libFrameCore.dylib"
xcrun swiftc -swift-version 5 -O -target "$task_arch-apple-macos14.0" -parse-as-library \
    -I "$check_dir" -L "$check_dir" -lFrameCore \
    -Xlinker -rpath -Xlinker '@executable_path' \
    Sources/FrameApp/StudioSessionStore.swift Sources/FrameApp/PhotoDropImporter.swift Sources/FrameApp/PhotoPaletteEdits.swift Sources/FrameApp/StudioModel.swift Checks/SelectionChecks.swift -o "$check_dir/SelectionChecks"
"$check_dir/SelectionChecks"
xcrun swiftc -swift-version 5 -O -target "$task_arch-apple-macos14.0" -parse-as-library \
    -I "$check_dir" -L "$check_dir" -lFrameCore \
    -Xlinker -rpath -Xlinker '@executable_path' \
    Sources/FrameApp/StudioSessionStore.swift Sources/FrameApp/PhotoDropImporter.swift Sources/FrameApp/PhotoPaletteEdits.swift Sources/FrameApp/StudioModel.swift Checks/DropChecks.swift -o "$check_dir/DropChecks"
"$check_dir/DropChecks"
xcrun swiftc -swift-version 5 -O -target "$task_arch-apple-macos14.0" -parse-as-library \
    -I "$check_dir" -L "$check_dir" -lFrameCore \
    -Xlinker -rpath -Xlinker '@executable_path' \
    Sources/FrameApp/StudioSessionStore.swift Sources/FrameApp/PhotoDropImporter.swift Sources/FrameApp/PhotoPaletteEdits.swift Sources/FrameApp/StudioModel.swift Checks/SessionChecks.swift -o "$check_dir/SessionChecks"
"$check_dir/SessionChecks"
