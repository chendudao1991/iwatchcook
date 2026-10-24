#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
tool_root=/workspace/toolchains
release=swift-6.0.3-RELEASE-ubuntu22.04
mkdir -p "$tool_root"
if [ ! -x "$tool_root/$release/usr/bin/swift" ]; then
  task_tmp=$(mktemp -d /tmp/wristnote-swift-install.XXXXXX)
  trap 'rm -rf "$task_tmp"' EXIT
  base=https://download.swift.org/swift-6.0.3-release/ubuntu2204/swift-6.0.3-RELEASE
  curl --fail --location --retry 2 "$base/$release.tar.gz" -o "$task_tmp/swift.tar.gz"
  curl --fail --location "$base/$release.tar.gz.sig" -o "$task_tmp/swift.tar.gz.sig"
  # Official Swift website repository; fingerprint is pinned below as well.
  curl --fail --location https://raw.githubusercontent.com/swiftlang/swift-org-website/main/keys/all-keys.asc \
    -o "$task_tmp/keys.asc"
  mkdir -m 700 "$task_tmp/gpg"
  gpg --homedir "$task_tmp/gpg" --import "$task_tmp/keys.asc"
  gpg --homedir "$task_tmp/gpg" --status-fd 1 --verify "$task_tmp/swift.tar.gz.sig" \
    "$task_tmp/swift.tar.gz" > "$task_tmp/status"
  rg '^\[GNUPG:\] VALIDSIG 52BB7E3DE28A71BE22EC05FFEF80A866B47A981F ' "$task_tmp/status"
  tar -xzf "$task_tmp/swift.tar.gz" -C "$tool_root"
fi
"$tool_root/$release/usr/bin/swift" --version
python3 -m pip install --target "$tool_root/wristnote-python" --upgrade -r scripts/check-requirements.txt
PYTHONPATH="$tool_root/wristnote-python" python3 scripts/check_project.py
WRISTNOTE_SWIFT_BIN="$tool_root/$release/usr/bin/swift" bash scripts/test_core.sh
