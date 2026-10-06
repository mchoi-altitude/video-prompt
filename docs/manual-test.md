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
| 2 | First recording: macOS asks for Screen Recording | Allow it in System Settings; macOS asks to Quit & Reopen the app |
| 3 | Open Chrome, press ⌃⌥⌘R | 3-2-1, red outline… then the control bar (● timer ❚❚ ✎ ■) at the top |
| 4 | Talk ~10 s; click ✎, circle something; click ✎ again | Red circle on screen, fades after ~3 s; clicks work again after ✎ off |
| 5 | Resize the Chrome window, keep talking, then ■ | "Transcribing on this Mac…", then the review panel |
| 6 | Review panel | Transcript is your words; frames show Chrome only; the circle is visible in a frame; later frames narrower |
| 7 | Press Return (Save & copy reference) | Toast "Saved…"; clipboard holds `@"…/prompt.md"` |
| 8 | Paste into Claude Code | Claude describes what you circled and asked for |
| 9 | Path B: ask Claude "call wait_for_next_recording" | Menu icon gets an amber dot; menu header "Claude is waiting…" |
| 10 | Record, then Send to waiting session | Claude answers from the recording; amber dot goes away |
| 11 | Pause/resume during a recording | Timer stops while paused; recording continues after resume |
| 12 | Recordings… | Rows with status/expiry; trash moves to the macOS Trash; Auto-delete picker works |

Results:

| Date | Who | Passed | Notes |
|---|---|---|---|
