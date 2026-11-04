# Bringing Video Prompt to Windows

**For Claude Code, running on the Windows machine.** Read this file, `CLAUDE.md` and "Updates after
building the Fedora app" in `docs/superpowers/specs/2026-11-04-windows-linux-design.md`. Then work
through this with the person at the keyboard.

The Fedora app in this folder already works, so adapt it rather than building a throwaway test. This
replaces the setup in `desktop-spike/README.md`, but its Windows checks (W1, W2 and hand-off) still apply.

## Ground rules

- **The person is your eyes.** You probably can't see overlays or judge how they behave. Give one short
  step at a time, say what to look for, and believe what they report over any log or test.
- **This repo is public.** Work on a `feat/windows-desktop` branch and don't push to `main`. Never commit
  recordings, screenshots, transcripts, usernames, hostnames or personal paths.
- **Ask before changing the machine,** including system settings, security tools and anything needing
  admin rights. Prefer per-project installs.
- **Keep Fedora working.** It can't be tested from Windows, so branch on the platform, keep Linux
  behavior unchanged, and tell the maintainer what to retest there.
- **Match the Mac,** unless Windows makes that impossible. See `Sources/VideoPrompt/`.
- **Keep it simple for the user.** On Fedora, every visible extra step made the experience worse.
- **Report failures honestly,** and stop to ask if something has taken about half a day without progress.

## What's Linux-only today

Found by reading the code, not by running it on Windows, so expect more.

| Where | Problem |
|---|---|
| `package.json` | `build` uses `cp`, and `start` passes `--ozone-platform=x11`, which is Linux only |
| `bin/vp-frames` | A shell script. It needs a form that works from PowerShell, Git Bash and WSL |
| `src/main/main.ts` (`root`) | The data folder should be `%LOCALAPPDATA%\VideoPrompt` on Windows |
| `src/main/main.ts` (`vpFrames`) | Points at the shell script |
| `src/main/main.ts` (overlay and bar) | `type: "notification"` is Linux only. The Fedora fixes for stacking may not apply |
| `src/main/main.ts` (`startFlow`) | Assumes a system dialog picks the screen or a region. See below |
| `src/process/tools.ts` | `findWhisper` looks in `/usr/bin` and for a name with no `.exe`. ffmpeg comes from `PATH` |
| `src/process/processor.ts` | `clicksLogged` is true on Windows, but nothing logs clicks yet. Set it false until something does, or the timeline will imply clicks it doesn't have |
| `src/core/timeline.ts` | `renderTimeline` needs the Windows and WSL command forms (design §5) |
| `src/ui/review.ts`, `src/ui/recordings.ts` | `file://` URLs split paths on `/`. Use a helper that handles `C:\` |
| `src/test/core.test.ts` | Runs `bin/vp-frames` and expects `/` in paths |
| `scripts/` | Bash, and the install steps are Fedora's. Windows needs its own package and install |

## Choosing what to record

Check this first, since it changes the design. We expect Windows to capture with no system dialog and
no region option, but nobody has confirmed that here.

If so, follow the Mac: Record whole screen, and Record selected area… with a drag-to-select step. That
picker needs writing, because Fedora's was removed before it was ever committed. It was a full-screen,
always-on-top transparent window with a dimmed background: drag to draw a rectangle, click once for the
whole screen, and Esc to cancel. With a picker, the app knows the area, so it can capture the whole
screen and crop. In `raw/session.json`, leave `regionFromDialog` unset, and `processor.ts` handles the
crop and coordinates. `locateRegion` and its faint pattern aren't needed.

## Order of work

1. **Run it.** Get `npm ci`, `npm test` and `npm start` working, with ffmpeg on `PATH` for now.
2. **Overlay (the biggest risk).** With a browser and a terminal open: do marks stay on top when switching
   apps and over a full-screen app? With Draw off, do clicks reach the app underneath? With Draw on, do
   they stay out of it? Can you always click the bar, and do Esc and Alt+D work? Does typing still go to
   the app underneath? Do marks reach the video?
3. **Control bar.** With `setContentProtection(true)`, is it missing from the video while marks stay
   visible? Is there a capture border? If hiding fails, place it outside the area, as on Fedora.
4. **Coordinates.** Mark a known on-screen object, and check the timeline's coordinates against a frame.
   Test across monitors with different scales if available.
5. **Everything else.** Microphone, pause, whisper, review, Recordings, auto-delete and Retry.
6. **Hand-off.** Paste the reference into a new Claude Code session in PowerShell, and in WSL using the
   `/mnt/c/...` path from a Copy WSL path button. Ask about something on screen. Use a data folder with a
   space in its path. Claude should run `vp-frames` without help. Note any path or quoting errors.
7. **Package.** Bundle Electron, whisper-cli and ffmpeg, with nothing else to install. Check ffmpeg's
   license for the build you bundle, and note the SmartScreen warning in the README. Publish nothing
   without the maintainer's approval, since releases here are public. Use a separate release, because
   `scripts/release-beta.sh` deletes and recreates `beta`.

Click rings need a native mouse hook, so leave them for after this works. The MCP plugin is out of scope.

## Lessons from Fedora

Don't assume these apply on Windows, but they show where to look.

- Stacking broke in several different ways. Keep the bar clickable whatever the stacking order.
- Global cursor position went stale. The windows' own pointer events were reliable.
- Resizing a canvas wipes it, and a window can reach full size only after it's shown.
- Capture altered colors, so don't rely on exact color values.
- ffmpeg can succeed without writing a file. Check that outputs exist.
- `npm ci` doesn't download Electron's program. It arrives the first time `electron` runs.
- Stop by process ID or a precise match, and never restart the app during someone's recording.

## Report back

Open a draft pull request. List what the person confirmed, what's untested, the Windows version, any
security tools, the monitors and their scales, and what needs retesting on Fedora.
