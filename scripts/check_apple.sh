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
result_path="${RUNNER_TEMP:-${TMPDIR:-/tmp}}/WristNoteAI-$(date +%s)-$$.xcresult"
if [ -n "${GITHUB_ENV:-}" ]; then
  echo "WRISTNOTE_RESULT_BUNDLE=$result_path" >> "$GITHUB_ENV"
fi
xcodebuild -project WristNoteAI.xcodeproj -scheme WristNoteAI \
  -destination "platform=iOS Simulator,id=$device_id" CODE_SIGNING_ALLOWED=NO \
  -resultBundlePath "$result_path" test
echo "XCTest result: $result_path"
summary_json="$result_path.summary.json"
if xcrun xcresulttool get test-results summary --help >/dev/null 2>&1; then
  xcrun xcresulttool get test-results summary --path "$result_path" > "$summary_json"
else
  # Xcode 15's result format. Xcode 16+ uses the new summary command above.
  xcrun xcresulttool get --path "$result_path" --format json > "$summary_json"
fi
python3 scripts/check_xcresult.py "$summary_json"
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  python3 scripts/check_xcresult.py "$summary_json" >> "$GITHUB_STEP_SUMMARY"
fi
