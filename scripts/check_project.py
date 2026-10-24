#!/usr/bin/env python3
"""Check manifest consistency and Swift grammar; this is NOT an Apple SDK build."""
from pathlib import Path
import sys
import yaml
from tree_sitter import Language, Parser
import tree_sitter_swift

ROOT = Path(__file__).resolve().parents[1]
errors = []
spec = yaml.safe_load((ROOT / "project.yml").read_text())
targets = spec["targets"]
phone = targets["WristNoteAI"]
watch = targets["WristNoteWatch"]
phone_id = phone["settings"]["base"]["PRODUCT_BUNDLE_IDENTIFIER"]
watch_id = watch["settings"]["base"]["PRODUCT_BUNDLE_IDENTIFIER"]

def require(condition, message):
    if not condition:
        errors.append(message)

require(phone["platform"] == "iOS" and watch["platform"] == "watchOS", "Target platforms mismatch")
require(watch["type"] == "application", "Use a modern, single-target watchOS app")
require(watch_id.startswith(phone_id + "."), "Watch Bundle ID must be prefixed by iPhone Bundle ID")
require(watch["info"]["properties"]["WKCompanionAppBundleIdentifier"] == phone_id, "Companion ID mismatch")
require(watch["info"]["properties"].get("WKApplication") is True, "Missing WKApplication")
require(watch["info"]["properties"].get("WKRunsIndependentlyOfCompanionApp") is True,
        "Watch must be allowed to run independently of the phone app")
require(any(d.get("target") == "WristNoteWatch" and d.get("embed") for d in phone["dependencies"]),
        "Watch app must be embedded in the phone app")
require("audio" in watch["info"]["properties"].get("UIBackgroundModes", []), "Watch background audio missing")
require(bool(watch["info"]["properties"].get("NSMicrophoneUsageDescription")), "Missing microphone disclosure")
require(bool(phone["info"]["properties"].get("NSSpeechRecognitionUsageDescription")), "Missing Speech disclosure")
for name, target in targets.items():
    for source in target["sources"]:
        require((ROOT / source).exists(), f"Missing source directory: {name}/{source}")

parser = Parser(Language(tree_sitter_swift.language()))
sources = sorted(path for directory in ["Shared", "iOSApp", "WatchApp", "Tests"]
                 for path in (ROOT / directory).rglob("*.swift")) + [ROOT / "Package.swift"]
for source in sources:
    tree = parser.parse(source.read_bytes())
    if tree.root_node.has_error:
        pending = [tree.root_node]
        while pending:
            node = pending.pop()
            if node.type == "ERROR" or node.is_missing:
                errors.append(f"{source.relative_to(ROOT)}:{node.start_point.row + 1}: {node.type}")
            pending.extend(reversed(node.children))
    if "WatchApp" in source.parts:
        require("import Speech" not in source.read_text(), f"watchOS must not import Speech: {source}")
if errors:
    print("\n".join(errors), file=sys.stderr)
    sys.exit(1)
print(f"PASS: project manifest consistency and {len(sources)} Swift syntax trees")
print("Not run by this check: Swift type checking, XcodeGen, Apple SDK build, device tests")
