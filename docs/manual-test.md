# Manual end-to-end test

Run before each release, on a real Mac (needs Screen Recording + Microphone permission).

```bash
scripts/build-app.sh --release && open "build/Video Prompt.app"
# For path B, start Claude Code with the plugin pointing at the app's server:
VIDEO_PROMPT_MCP="$PWD/build/Video Prompt.app/Contents/MacOS/vp-mcp" claude --plugin-dir plugins/video-prompt
```

| # | Step | Expected |
|---|---|---|
| 1 | Click the ◉ icon in the menu bar | Menu: Record Chrome window (with the tab title), whole screen, area…, another window…, Recordings… |
| 2 | First recording: macOS asks for Screen Recording, then Microphone | Both prompts name **Video Prompt** (never your terminal). Allow; Quit & Reopen restarts only Video Prompt. The recording starts once (no second stream) |
| 3 | Open Chrome, press ⌃⌥⌘R | 3-2-1 countdown, then the control bar (● timer ❚❚ ✎ ■) at the top; menu icon turns red |
| 4 | Talk ~10 s; click ✎, circle something; click ✎ again | Red circle on screen, fades after ~3 s; clicks work again after ✎ off |
| 5 | Resize the Chrome window, keep talking, then ■ | "Transcribing on this Mac…", then the review panel |
| 6 | Review panel | The video plays (muted) showing only Chrome, with your circle and red click rings; the transcript is your words |
| 7 | Press Return (Save & copy reference) | Toast "Saved…"; clipboard holds `@"…/timeline.md"` |
| 8 | Paste into Claude Code | Claude describes what you circled and asked for |
| 9 | Path B: ask Claude "call wait_for_next_recording" | Menu icon gets an amber dot; menu header "Claude is waiting…" |
| 10 | Record, then Send to waiting session | Claude answers from the recording; amber dot goes away |
| 11 | Pause/resume during a recording | Timer stops while paused; recording continues after resume |
| 12 | Recordings… | Rows with status/expiry; trash moves to the macOS Trash; Auto-delete picker works |
| 13 | Draw, then Undo or Clear, then Stop | Undone marks aren't described in timeline.md |
| 14 | While the review panel is open, click into Chrome | The panel stays; closing it saves (toast), Recordings shows it |
| 15 | Double-click ■ | One processing run, no error toast |
| 16 | Stop from the macOS screen-recording indicator in the menu bar | Toast "Recording stopped…", then the review panel with what was recorded |
| 17 | Start of the video | No countdown overlay at 0:00 |

Results:

| Date | Who | Passed | Notes |
|---|---|---|---|
