## Change

The repository previously contained only a placeholder README. Add the first native WristNoteAI iPhone and Apple Watch implementation from the supplied PRD: independent Watch recording, durable file synchronization with acknowledgements and deduplication, Chinese post-recording transcription with 40-second checkpoints, provisional live subtitles, editing and TXT/audio export.

Keep local recording independent of live connectivity. Default to on-device Speech recognition; online Apple recognition requires explicit user opt-in. Add XcodeGen configuration, native CI entry points, architecture notes and an unchanged device acceptance checklist.

## Validation

- Linux Swift 6.0.3: 10 XCTest tests passed, 0 failures. Four xcresult-validator tests passed.
- Swift compiler parsing, 19-file syntax-tree and manifest checks, shell syntax and whitespace checks passed.
- [Remote macOS run 40102949039](https://github.com/chendudao1991/iwatchcook/actions/runs/40102949039) for source commit 59ddecc: original logs confirm XcodeGen execution, iOS and watchOS simulator BUILD SUCCEEDED, and iOS simulator XCTest: **10 passed / 0 failed / 0 skipped**. The native-validation artifact contains the raw build log, xcresult and test summary.
- This local machine remains Linux. Physical-device tests, signing, sustained background recording and Speech accuracy **not verified**.

## Review focus

This should remain a draft until paired-device acceptance passes. Validate Watch background recording, signing, interrupted CAF recovery, WC transfer behaviour, Speech model availability and long-session energy/storage usage. The phone publishes checkpoints only after atomic persistence succeeds. Reconnected live streams have distinct IDs; retries back off with a finite budget. Segment boundaries and live-window rotations may lose provisional words; only final file transcription is authoritative. PDF/Word export, pause/resume, iCloud and summaries remain out of scope.

The paired-device procedure is in docs/DEVICE_TEST_PLAN.md. No physical-device acceptance items have been marked complete.
