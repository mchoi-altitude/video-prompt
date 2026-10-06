# Known issues

Deferred from the code reviews of Plans 1–2 and the video-first change (2026-10-06). None of
them blocks the internal beta. The suggested first fixes are **#1**, **#6** and **#7**, since
those are the ones a tester is likely to hit.

## Things a user might notice

| # | Issue | What you'd see | Where |
|---|---|---|---|
| 1 | The timer pauses while a menu is open | The control bar's clock and cursor tracking freeze while any menu is open, then catch up. The timers run in the default run-loop mode; add them in `.common`. | `Sources/VideoPrompt/AppDelegate.swift` (timers) |
| 2 | "Record another window…" is labelled "Chrome window" | The countdown and review panel call any picked window "Chrome window". | `AppDelegate.label`, `ReviewView.modeLabel` |
| 3 | The pickers can get stuck | ⌘-Tab while picking an area or window hides the picker but leaves it waiting. Esc or picking again recovers. | `AreaPicker`, `WindowPicker` (`hidesOnDeactivate`) |
| 4 | Area selection can span two screens | Dragging across monitors gives a rectangle partly off the recorded display (that part is padded). Clamp it to the screen where the drag started. | `AreaPicker` |
| 5 | Retry edge cases | A double Retry, or Retry during a recording, can reset the controller. There's no "Transcribing…" toast on Retry. | `AppDelegate.retry` |
| 6 | Shortcut conflicts are silent | If another app owns ⌃⌥⌘R or ⌥D, registration fails and that's only logged. Tell the user, e.g. in Setup. | `Hotkeys.register` |
| 7 | Speech-to-text failure fails the whole recording | If whisper crashes, the recording is `processingFailed` instead of saved with "transcription unavailable". | `Processor.run` (transcription step) |
| 8 | An edited transcript doesn't update the title | Fixing the first sentence in review leaves the old title in Recordings. | `finalize` |

## Performance and polish

| # | Issue | Effect | Where |
|---|---|---|---|
| 9 | Inefficient rendering on 5K displays | Each kept frame turns the whole display into an image before cropping: slower on 5K/6K screens, though memory stays flat. Point a CGContext at the crop's bytes instead. Also, `copyNextSampleBuffer()` blocks inside an async function. | `Sources/VPMedia/WindowVideo.swift` |
| 10 | The window list is read 10× a second | Small background CPU use while recording. Query only the tracked window (`optionIncludingWindow`). | `CGWindowListSource` |
| 11 | 1–2 px clipped at the video edge | The canvas is rounded down to even sizes while the crop rounds outward, so the right or bottom pixel column can be clipped. | `renderWindowVideo` |
| 12 | The example command in the timeline uses fixed times | It always shows `--from 12.0 --to 14.0`, which can be past the end of a short recording. Use a time from the timeline. | `renderTimeline` |
| 13 | The trash sweep stops at the first failure | One recording that can't be trashed blocks the rest until the next hourly sweep. | `Store.sweep` |
| 14 | A file handle can leak | On some failed recording starts, `events.jsonl` stays open until the app quits. | `RawRecorder` |
| 15 | Speech-to-text blocks a background thread | `readDataToEndOfFile` / `waitUntilExit` inside async code. Harmless at one recording at a time. | `WhisperCLITranscriber.words` |

## Only with several Claude Code sessions at once

| # | Issue | Effect | Where |
|---|---|---|---|
| 16 | Two waits in one session share one waiter file | The first wait to finish clears the "Claude is waiting" dot while the other is still waiting. | `MCPServer.waitForNext` |
| 17 | A cancelled request still gets a reply | After Esc in Claude Code, the server still answers the cancelled call. The MCP spec says it SHOULD NOT; harmless in practice. | `MCPServer.start` / `handle` |

## Resolved since review

- A missing speech-to-text engine was reported as "no narration". It now says "transcription unavailable" (internal beta).
- A recording stuck in "processing" after a crash is recovered at launch as Processing failed · Retry (Plan 2).
- A failed frame grab failing the whole recording no longer applies, since keyframes were removed in the video-first change.
