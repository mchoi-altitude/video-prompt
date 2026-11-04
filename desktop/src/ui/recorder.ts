// Hidden window that holds the capture stream, so Pause and Resume don't reopen the system dialog.
{
  let stream: MediaStream | null = null;
  let recorder: MediaRecorder | null = null;
  let finished: Promise<void> = Promise.resolve();

  const startCapture = async () => {
    const display = await navigator.mediaDevices.getDisplayMedia({ video: { frameRate: 10 }, audio: false });
    stream = display;
    // A missing or denied microphone still records, and the timeline says so.
    try {
      const mic = await navigator.mediaDevices.getUserMedia({ audio: { echoCancellation: false, noiseSuppression: true }, video: false });
      mic.getAudioTracks().forEach((t) => stream!.addTrack(t));
    } catch (e) {
      console.error("no microphone", e);
    }
    const probe = document.createElement("video");
    probe.muted = true;
    probe.srcObject = stream;
    await new Promise<void>((resolve) => {
      probe.onloadedmetadata = () => resolve();
    });
    return { width: probe.videoWidth, height: probe.videoHeight };
  };

  const startSegment = async () => {
    const mimeType = "video/webm;codecs=vp8,opus";
    recorder = new MediaRecorder(stream!, { mimeType, videoBitsPerSecond: 8_000_000, audioBitsPerSecond: 96_000 });
    // Chunks go in order, one at a time, so the file on disk is always valid up to the last one.
    let writing: Promise<void> = Promise.resolve();
    recorder.ondataavailable = (e) => {
      writing = writing.then(async () => vp.segmentChunk(await e.data.arrayBuffer()));
    };
    const stopped = new Promise<void>((resolve) => {
      recorder!.onstop = () => void writing.then(resolve);
    });
    finished = stopped;
    await new Promise<void>((resolve) => {
      recorder!.onstart = () => resolve();
      recorder!.start(1000);
    });
  };

  const stopSegment = async () => {
    if (recorder && recorder.state !== "inactive") recorder.stop();
    await finished;
    recorder = null;
  };

  const stopCapture = () => {
    stream?.getTracks().forEach((t) => t.stop());
    stream = null;
  };

  // Reads the newest frame from a copy of the stream, while measuring a region's position.
  let probeTrack: MediaStreamTrack | null = null;
  let latest: any = null;

  const startProbe = () => {
    probeTrack = stream!.getVideoTracks()[0].clone();
    const reader = new (window as any).MediaStreamTrackProcessor({ track: probeTrack }).readable.getReader();
    void (async () => {
      for (;;) {
        const { value, done } = await reader.read();
        if (done) return;
        latest?.close();
        latest = value;
      }
    })();
  };

  const readProbe = (inset: number) => {
    if (!latest) throw new Error("no frame yet");
    const width: number = latest.displayWidth;
    const height: number = latest.displayHeight;
    const canvas = new OffscreenCanvas(width, height);
    const ctx = canvas.getContext("2d", { willReadFrequently: true })!;
    ctx.drawImage(latest, 0, 0);
    const pixel = (x: number, y: number) => [...ctx.getImageData(x, y, 1, 1).data].slice(0, 3);
    return { width, height, first: pixel(inset, inset), last: pixel(width - 1 - inset, height - 1 - inset) };
  };

  const stopProbe = () => {
    probeTrack?.stop();
    probeTrack = null;
    latest?.close();
    latest = null;
  };

  // Called from the main process with a user gesture.
  Object.assign(window, { startCapture, startSegment, stopSegment, stopCapture, startProbe, readProbe, stopProbe });
}
