{
  const el = <T extends HTMLElement>(id: string) => document.getElementById(id) as T;
  const timer = el<HTMLSpanElement>("timer");
  const caption = el<HTMLDivElement>("caption");
  const draw = el<HTMLButtonElement>("draw");
  const pause = el<HTMLButtonElement>("pause");
  const tools: Tool[] = ["pen", "arrow", "box"];
  let t = { elapsedBefore: 0, runningSince: null as number | null, paused: false };
  let drawing = false;

  const update = () => {
    const ms = t.elapsedBefore + (t.runningSince === null ? 0 : Date.now() - t.runningSince);
    const s = Math.floor(ms / 1000);
    timer.textContent = `${Math.floor(s / 60)}:${String(s % 60).padStart(2, "0")}`;
    // Soft warning at 3:00, no hard stop.
    if (s >= 180) caption.textContent = "Long recordings give Claude many frames. Wrap up soon?";
    else if (drawing) caption.textContent = "Drawing · clicks don’t reach apps · Esc to stop";
    else caption.textContent = "Alt+D to draw";
  };

  const selectTool = (tool: Tool) => {
    for (const x of tools) el(x).classList.toggle("selected", x === tool);
    vp.setTool(tool);
  };

  for (const tool of tools) el(tool).onclick = () => selectTool(tool);
  draw.onclick = () => vp.toggleDraw();
  pause.onclick = () => vp.togglePause();
  el("stop").onclick = () => vp.stop();
  el("undo").onclick = () => vp.undo();
  el("clear").onclick = () => vp.clear();
  vp.onDrawChanged((on) => {
    drawing = on;
    draw.classList.toggle("on", on);
    document.body.classList.toggle("drawing", on);
    update();
  });
  vp.onTimer((next) => {
    t = next;
    document.body.classList.toggle("paused", t.paused);
    el("pause-icon").style.display = t.paused ? "none" : "";
    el("play-icon").style.display = t.paused ? "" : "none";
    const label = t.paused ? "Resume" : "Pause";
    pause.title = label;
    pause.setAttribute("aria-label", label);
    draw.disabled = t.paused;
    update();
  });

  document.documentElement.addEventListener("mouseenter", () => vp.barHover(true));
  document.documentElement.addEventListener("mouseleave", () => vp.barHover(false));

  update();
  setInterval(update, 250);
}
