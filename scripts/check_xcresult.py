#!/usr/bin/env python3
"""Reject empty/skipped/failed XCTest runs in the xcresult just written by check_apple.sh."""
import argparse
import json
from pathlib import Path


def counts(result):
    if "totalTestCount" in result:
        return (int(result["totalTestCount"]), int(result["passedTests"]),
                int(result["failedTests"]), int(result.get("skippedTests", 0)))
    metrics = result["metrics"]
    total = int(metrics["testsCount"]["_value"])
    failed = int(metrics.get("testsFailedCount", {}).get("_value", 0))
    skipped = int(metrics.get("testsSkippedCount", {}).get("_value", 0))
    return total, total - failed - skipped, failed, skipped


def validate(result, minimum=24):
    total, passed, failed, skipped = counts(result)
    if passed < minimum or failed or min(total, passed, failed, skipped) < 0:
        raise ValueError(f"Insufficient XCTest result: total={total}, passed={passed}, failed={failed}, skipped={skipped}")
    return f"XCTest: {passed} passed, {failed} failed, {skipped} skipped ({total} total)."


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("result_json", type=Path)
    args = parser.parse_args()
    print(validate(json.loads(args.result_json.read_text())))
