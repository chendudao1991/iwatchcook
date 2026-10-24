## Change

The repository previously contained only a placeholder README. Add the first native WristNoteAI iPhone and Apple Watch implementation from the supplied PRD: independent Watch recording, durable file synchronization with acknowledgements and deduplication, Chinese post-recording transcription with 40-second checkpoints, provisional live subtitles, editing and TXT/audio export.

Keep local recording independent of live connectivity. Default to on-device Speech recognition; online Apple recognition requires explicit user opt-in. Add XcodeGen configuration, native CI entry points, architecture notes and an unchanged device acceptance checklist.

## Validation

- Linux Swift 6.0.3: 5 XCTest tests passed, 0 failures.
- Swift compiler parsing, 16-file syntax-tree and manifest checks, shell syntax and whitespace checks passed.
- Apple SDK type checking, XcodeGen execution, native builds, simulator and physical-device checks **not run**: this environment is Linux without Xcode or Apple SDKs.

## Review focus

This should remain a draft until macOS builds and paired-device acceptance pass. Validate Watch background recording, modern watchOS target embedding/signing, interrupted CAF recovery, WC transfer behaviour, Speech model availability and long-session energy/storage usage. Segment boundaries and live-window rotations may lose provisional words; only final file transcription is authoritative. PDF/Word export, pause/resume, iCloud and summaries remain out of scope.
