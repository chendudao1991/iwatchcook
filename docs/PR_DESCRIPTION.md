## Change

The repository previously contained only a placeholder README. Add the first native WristNoteAI iPhone and Apple Watch implementation from the supplied PRD: independent Watch recording, durable file synchronization with acknowledgements and deduplication, Chinese post-recording transcription with 40-second checkpoints, provisional live subtitles, editing and TXT/PDF/RTF/audio export.

Keep local recording independent of live connectivity. Default to on-device Speech recognition; online Apple recognition requires explicit user opt-in. Add XcodeGen configuration, native CI, architecture notes and evidence-linked acceptance tracking. Manual local saving recovery preserves unreadable audio and does not reset corrupt indexes.

## Validation

- Linux Swift 6.0.3: 10 XCTest tests passed, 0 failures. Four xcresult-validator tests passed.
- Swift compiler parsing, 23-file syntax-tree and manifest checks, shell syntax and whitespace checks passed.
- [Remote macOS run 40103871821](https://github.com/chendudao1991/iwatchcook/actions/runs/40103871821) for source commit 23c8c4e: original logs confirm XcodeGen execution, iOS and watchOS simulator BUILD SUCCEEDED, and iOS simulator XCTest: **24 passed / 0 failed / 0 skipped**. The native-validation artifact contains the raw build log, xcresult and test summary.
- Native integration tests exercise actual CAF import, duplicate/tombstone handling, orphan replacement, corrupt index protection, checkpoint and Watch library recovery, Chinese PDF extraction, long-text pagination and RTF round trips. WatchLibrary tests run its actual source on iOS Simulator, not on Watch hardware.
- This local machine remains Linux. Physical-device tests, signing, sustained background recording and Speech accuracy **not verified**.

## Review focus

This should remain a draft until paired-device acceptance passes. Validate Watch background recording, signing, interrupted live-capture recovery, WC transfer behaviour, Speech model availability and long-session energy/storage usage. The phone publishes checkpoints only after atomic persistence succeeds. Reconnected live streams have distinct IDs; retries back off with a finite budget. Segment boundaries and live-window rotations may lose provisional words; only final file transcription is authoritative. RTF can be opened in Word but is not .docx. Native .docx, pause/resume, iCloud and summaries remain out of scope.

The paired-device procedure is in docs/DEVICE_TEST_PLAN.md. No physical-device acceptance items have been marked complete.
