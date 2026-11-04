{
  const el = <T extends HTMLElement>(id: string) => document.getElementById(id) as T;
  const status = el<HTMLDivElement>("status");
  const form = el<HTMLDivElement>("form");
  const video = el<HTMLVideoElement>("video");
  const transcript = el<HTMLTextAreaElement>("transcript");
  const note = el<HTMLTextAreaElement>("note");
  const hint = el<HTMLParagraphElement>("hint");
  let ready = false;

  const copy = () => vp.reviewCopy({ transcriptText: transcript.value, note: note.value });

  vp.onReviewReady((d) => {
    ready = true;
    status.style.display = "none";
    form.style.display = "block";
    video.src = `file://${d.video.split("/").map(encodeURIComponent).join("/")}`;
    // Starts muted, like the Mac's preview.
    video.muted = true;
    transcript.value = d.transcript;
    note.value = d.note;
    if (d.transcription === "unavailable") hint.textContent = "Speech-to-text didn't run, so there's no transcript. Type what you said here if it matters.";
    else if (d.transcription === "noAudio") hint.textContent = "The microphone was off for this recording.";
    else if (d.transcription === "noSpeech") hint.textContent = "No speech was detected.";
  });
  vp.onReviewFailed((error) => {
    status.textContent = `Processing failed. You can retry it from Recordings. ${error}`;
  });

  el("copy").onclick = copy;
  el("discard").onclick = () => vp.reviewDiscard();
  addEventListener("keydown", (e) => {
    // Return copies, unless the cursor is in a text box.
    if (e.key === "Enter" && ready && !(document.activeElement instanceof HTMLTextAreaElement)) copy();
  });
}
