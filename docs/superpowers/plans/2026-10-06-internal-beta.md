# Internal Beta Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Teammates with access to the private repo install and update Video Prompt with one
command. No Apple Developer account, notarization, update feed or cask (those stay in the
public-release plan).

**Architecture:** `release-beta.sh` builds the app signed with the "Video Prompt Dev" identity,
zips it with `install.sh`, and replaces the `beta` GitHub Release. `install.sh` (run after
`gh release download`, which leaves no quarantine flag) installs the app, makes sure whisper and
its model are present, and prints the plugin commands. A first-run setup window (as in the
prototype's Setup board) walks through permissions, Claude Code and a test recording.

**Spec:** `docs/superpowers/specs/2026-10-06-video-prompt-design.md` §3.0 (setup), §9 (identity).

## Global Constraints

- Same bundle id and the same signing identity for every beta build (so the permission grants persist).
- `install.sh` must be safe to re-run (update = run it again). It never uses sudo, and asks before installing Homebrew packages.
- The model is `ggml-base.en.bin`, pinned by SHA-256 in `install.sh`.
- When speech-to-text is missing, the timeline must say **"transcription unavailable"**, not "no narration was detected".

### Task 1: Transcription-unavailable wording (VPCore/VPProcess)
`Manifest.transcription: TranscriptionState` (`.ok`, `.noSpeech`, `.unavailable`), rendered in timeline.md.
Tests: `unavailableTranscriberIsNotSilence`, plus the updated golden.

### Task 2: Setup model + window (VPApp + app)
`SetupModel` with steps `screen` (`CGPreflightScreenCaptureAccess`), `microphone`
(`AVCaptureDevice.authorizationStatus`), `speech` (`WhisperCLITranscriber.fromEnvironment`),
`claude` (`Waiters.pluginSeen()`), and `done` when the first three are resolved. It's shown on first
launch and from the menu's **Setup…** item; the settings flag `setupShown`.
Tests: `stepsFollowSystemState` (with fakes), `doneNeedsPermissionsAndSpeech`.

### Task 3: install.sh + release-beta.sh + README beta section
Verified by running release-beta.sh with `--dry-run` (no upload), then install.sh against the dry-run zip into a temp prefix (`VP_PREFIX`).
