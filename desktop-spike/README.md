# Windows and Fedora test guide

**For Claude Code, running on the machine under test.** Read this whole file, then run the section
for your system with the person at the keyboard.

## Why this exists

We plan to build Video Prompt for Windows and Fedora in Electron. See
[the design](../docs/superpowers/specs/2026-11-04-windows-linux-design.md), mainly §4–§7 and §9, and
`CLAUDE.md`. Before the full build, this test answers whether Electron can do the risky parts on real
machines. The result decides whether we continue, change approach, or revise the estimate.

## Ground rules

- **This code is throwaway.** Keep it small and put it in `desktop-spike/`. Skip tests, polish and
  shared abstractions. Don't change anything else in the repo.
- **This repo is public. Only commit the test code and `RESULTS.md`.** Never commit recordings,
  screenshots, frames or transcripts. Keep results free of usernames, hostnames, personal paths
  and anything visible on the person's screen. Check `git status` and the diff before every commit.
- **Stay on the `spike/windows-linux` branch.** Pull before you push. Never push to `main`.
- **Ask before changing the machine.** That covers `sudo`, system packages, KWin rules, Windows
  settings and anything outside this repo. Prefer per-project installs. Use exact dependency versions.
- **The person is your eyes.** You probably can't see overlays or judge how they behave. Tell them
  exactly what to do and what to look for, one step at a time, and record what they report. Keep
  each step short.
- **Report failures honestly.** Try the listed fallback, then write down what happened. A clear "this
  fails" is a useful result, so don't redefine a check to make it pass.
- **Stop and ask** if a check has taken about half a day without progress.

## Setup

Node.js LTS and an exact Electron version are needed, with `desktop-spike/` as the project folder.
Bundle ffmpeg through an npm package such as `ffmpeg-static`.

Record the environment in `RESULTS.md`:

- **Fedora:** Fedora version, `plasmashell --version`, `echo $XDG_SESSION_TYPE`, monitors and each
  one's scale, Electron version.
- **Windows:** Windows version and build, x64 or ARM, monitors and each one's scale, whether it's a
  company-managed machine or has security tools, Electron version.

## The test app

Build one small Electron app with these pieces:

1. **Area picker:** a full-screen window where you drag a rectangle.
2. **Drawing layer:** a transparent, always-on-top, full-screen window with a red pen. With Draw off,
   clicks go through to apps underneath. With Draw on, the mouse draws.
3. **Control bar:** a small always-on-top window with Draw, Pause and Stop.
4. **Recorder:** capture the whole monitor with the mic at 10 fps, one file per pause.
5. **Processor:** use ffmpeg to join the segments and crop to the selected area, producing `video.mp4`.

Add a tiny log of drawn stroke points so positions can be compared with the video.

## Fedora Plasma checks

**F1. Drawing layer (the most important check).** With a browser and a terminal open:

- Do marks stay on top when clicking other windows, switching apps or opening a full-screen app?
- With Draw off, do clicks reach the app underneath? With Draw on, do they stay out of it?
- Do marks show up in the video?
- Does the layer take keyboard focus away from the app underneath?

If it fails, try native Wayland vs XWayland (`--ozone-platform=x11`). Then ask before trying a KWin
window rule. **If it still fails, stop and report: this is what would send us to Qt.**

**F2. Screen-share dialog.**

- How often does the dialog appear? Ideally only on the first recording.
- Can the app tell which monitor was chosen?
- With multiple monitors, can a "Change monitor" action bring the dialog back? What happens when the
  remembered monitor is unplugged?

If Electron's own capture shows the dialog every time, try the restore-token approach in
`prototype/screen_prompt/capture/linux.py`, and report how much harder that makes things.

**F3. Coordinates and shortcuts.**

- Draw around a known on-screen object, then extract a frame. Do logged stroke points map to the right
  video pixels? Is the crop exactly the selected area? Test at 100% and, with permission, a fractional
  scale such as 125% or 150%.
- Does a global shortcut (Ctrl+Alt+Shift+R) work while another app has focus? Does it ask for approval?
  A failure here isn't blocking, because the tray and control bar can do everything.
- Does the tray icon appear and work?
- Is the control bar left out of the video when it's outside the selected area?

## Windows checks

**W1. Hiding the control bar.**

- With `setContentProtection(true)` on the bar, is it missing from the video while drawn marks stay visible?
- Does a colored capture border appear? Does the capture work while the bar is hidden from it?
- Do the F1 drawing-layer questions pass here too?
- Do coordinates line up as in F3, including across monitors with different scales?

If hiding fails, keep the bar outside the area as on Fedora, and report it.

**W2. Click hook.**

- Can a small native mouse hook log clicks in other apps without admin rights?
- Do antivirus or company security tools object? Does Windows warn about the unsigned app?

If it fails, plan to ship without click rings, as on Fedora.

## Hand-off check (both systems)

Create a folder **with a space in its path** containing:

- `video.mp4`: about 20 s, made with ffmpeg, showing a plain background and a counter, with one
  **randomly chosen word on screen for about 0.4 s at a random time**. Don't tell the person or
  record the word or time anywhere Claude could find them, except a sealed note file outside that
  folder for checking the answer.
- `timeline.md`: follow `Tests/VPCoreTests/Golden/timeline.md`, with the §7 changes in the design and
  the real paths. Say only that a word flashes briefly, with no time given. On Windows, include the
  §5 command forms for Windows shells and WSL.
- A minimal `vp-frames` command: same arguments and output as `Sources/vp-frames/main.swift`, built
  on the bundled ffmpeg. It must run without needing Node, Python or ffmpeg installed for the user
  if at all possible. If that isn't practical in the test, say so in the results.

Then have the person open a **new** Claude Code session in a different folder, paste only the path
to `timeline.md`, and ask: "What word flashes in this recording?"

Run this from:

- **Fedora:** Claude Code in the normal terminal.
- **Windows:** Claude Code in PowerShell, including whichever shell it uses for commands, and in WSL if
  installed, using the `/mnt/c/...` path.
- **If convenient, on either system:** Claude Desktop and Conductor, noting whatever happens.

Pass means Claude reads the timeline, runs `vp-frames` without help and finds the right word. Note how
many tries and any path or quoting errors.

## Report back

Fill in `RESULTS.md`, check it's free of personal details, then commit it with the test code and
push. The person may need write access to this repo, or can open a pull request from a fork.

End by telling the person the overall verdict, and that the Mac-side session can now pull the branch
and read the results.
