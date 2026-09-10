#!/bin/sh
set -eu
task_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
task_build="$task_dir/builds"
task_app="$task_build/XP Farmers Kick Chat.app"
mkdir -p "$task_app/Contents/MacOS" "$task_build/module-cache"
xcrun swiftc -swift-version 5 -module-cache-path "$task_build/module-cache" \
  -framework AppKit "$task_dir/main.swift" -o "$task_app/Contents/MacOS/KickChat"
cp "$task_dir/Info.plist" "$task_app/Contents/Info.plist"
printf '%s\n' "$task_app"
