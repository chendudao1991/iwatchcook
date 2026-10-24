#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift_bin="${WRISTNOTE_SWIFT_BIN:-swift}"
test_root="${WRISTNOTE_TEST_ROOT:-/tmp/wristnote-core}"
mkdir -p "$test_root"
# The cloud user's home is read-only. Keep compiler/SPM caches in the task workspace.
export CLANG_MODULE_CACHE_PATH="$test_root/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$test_root/swift-cache"
"$swift_bin" test --jobs 2 --scratch-path "$test_root/build" \
  --cache-path "$test_root/spm-cache" --config-path "$test_root/spm-config" \
  --security-path "$test_root/spm-security"
