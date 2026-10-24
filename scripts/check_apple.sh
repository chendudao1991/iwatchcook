#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
command -v xcodegen >/dev/null
command -v xcodebuild >/dev/null
xcodegen generate
xcodebuild -project WristNoteAI.xcodeproj -scheme WristNoteAI \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project WristNoteAI.xcodeproj -scheme WristNoteWatch \
  -destination 'generic/platform=watchOS Simulator' CODE_SIGNING_ALLOWED=NO build
device_id=$(xcrun simctl list devices available --json | python3 -c '
import json, sys
devices = json.load(sys.stdin)["devices"]
ids = [d["udid"] for runtime, ds in devices.items() if "iOS" in runtime
       for d in ds if "iPhone" in d["name"] and d.get("isAvailable")]
if not ids: sys.exit("No available iPhone simulator")
print(ids[0])
')
result_path="${TMPDIR:-/tmp}/WristNoteAI-$(date +%s)-$$.xcresult"
xcodebuild -project WristNoteAI.xcodeproj -scheme WristNoteAI \
  -destination "platform=iOS Simulator,id=$device_id" CODE_SIGNING_ALLOWED=NO \
  -resultBundlePath "$result_path" test
echo "XCTest result: $result_path"
