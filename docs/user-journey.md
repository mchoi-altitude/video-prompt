# User journey (draft)

Status: **draft for discussion.** Items marked **❓ Decide** are open questions; the
**Proposal** under each is a starting point, not a decision.

## Who and why

A developer is working with Claude Code and wants to show rather than type: "this button,
this spacing, this flow is broken — here's what I want instead." Typing that out loses the
visual context. Screenshots lose the sequence and the explanation.

## 0. One-time setup

1. Install the app (`.dmg` or `brew install --cask screen-prompt`).
2. Install the Claude Code plugin, which connects recordings to Claude Code sessions.
3. First recording: macOS asks for Screen Recording and Microphone permission.

> **❓ Decide:** do we need an onboarding window, or is a first-run checklist in the menu
> enough? **Proposal:** a tiny first-run window with two checkmarks (permissions, plugin
> detected) and a "Test recording" button.

## 1. Start

The user is in the middle of a task and has something to show.

1. Click the menu-bar icon (or press a global shortcut).
2. Choose **Whole screen** or **Select area** (drag a rectangle).
3. A small floating control bar appears: ● Record / ❚❚ Pause / ■ Stop / ✎ Draw / timer.
4. Recording starts after a short 3-2-1 countdown.

> **❓ Decide:** which shortcut, and does it remember the last choice (screen vs area) so
> one keypress starts recording? **Proposal:** ⌃⌥⌘R; it remembers the last mode.
>
> **❓ Decide:** should the control bar appear in the video? **Proposal:** no (it's excluded
> from capture), but the drawings are included.

## 2. Show and tell

The user talks through what they want while using the screen normally.

- **Drawing:** toggle ✎ (or hold a modifier key) to draw on top of everything with the mouse.
  While drawing, clicks don't reach the apps underneath. Toggle off to interact again.
- **Pause / resume:** for example to open another window or think. Nothing is recorded while
  paused.
- **Cursor:** recorded throughout, so "this one here" can be resolved.

> **❓ Decide:** do drawings stay until cleared, or fade after about 3 seconds?
> **Proposal:** fade by default (so the screen stays usable), with an option to pin.
>
> **❓ Decide:** which tools? **Proposal (v1):** pen + arrow + rectangle, one color (red),
> undo, clear. A highlighter can wait.
>
> **❓ Decide:** a time limit? Long recordings mean many frames for Claude.
> **Proposal:** a soft warning at 3 minutes.

## 3. Stop and review

1. Click ■ Stop.
2. A few seconds of processing (transcription runs locally; audio never leaves the Mac).
3. A small review panel shows the transcript and keyframe thumbnails.
   - The user can fix transcript mistakes, remove frames, or add a typed note.
   - **Send to Claude** / **Copy reference** / **Discard**.

> **❓ Decide:** review step every time, or send straight away? **Proposal:** review panel
> with **Send** focused, so pressing Return sends immediately. Power users can turn review off.

## 4. Hand-off to Claude Code

This is the biggest open question: **which session gets it?**

- **Option A, pull (MCP):** the user tells Claude in any session "look at my recording."
  Claude calls `get_latest_recording` and sees the frames and narration inline. This is
  simple and reliable, and works with several sessions open.
- **Option B, Claude asks for it:** Claude says "can you show me?" and calls
  `wait_for_next_recording`. When the user stops, the recording goes straight to that session.
- **Option C, push:** the app sends the recording into "the active session" without being
  asked. Hard to do reliably: what's active when there are several terminals or windows?
- **Fallback:** copy `@…/prompt.md` to the clipboard, so the user can paste it anywhere.

> **❓ Decide:** **Proposal:** A + B + the clipboard fallback for v1; revisit C later.

## 5. Claude acts on it

Claude receives:

- The full narration (the "prompt").
- A timeline interleaving narration sentences, keyframes, and drawing notes such as
  "the user circled the area (326,86)–(672,238)".
- Instructions to ask before large changes if the narration is ambiguous.

Then Claude works as usual. It can refer back to "frame 3" in its replies.

## 6. Afterwards

> **❓ Decide:** retention. **Proposal:** keep the last 20 recordings locally and auto-delete
> older ones; there's an "Open recordings folder" menu item.
>
> **❓ Decide:** sharing with teammates (for example attaching a recording to a PR or issue)?
> **Proposal:** out of scope for v1.
>
> **❓ Decide:** privacy. Frames go to Claude. Do we need "blur region" or "don't capture
> these apps"? **Proposal:** out of scope for v1, but the review step lets users drop frames.

## Success looks like

- From "I want to show Claude this" to Claude having it: **under 10 seconds of overhead**
  beyond the recording itself.
- Claude's first response shows it understood which UI element was meant, without follow-up
  questions, in most cases.
