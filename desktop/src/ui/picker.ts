{
  const box = document.getElementById("box") as HTMLDivElement;
  const hint = document.getElementById("hint") as HTMLDivElement;
  let start: { x: number; y: number } | null = null;

  const dragRect = (e: MouseEvent) => ({
    x: Math.min(start!.x, e.clientX),
    y: Math.min(start!.y, e.clientY),
    w: Math.abs(e.clientX - start!.x),
    h: Math.abs(e.clientY - start!.y),
  });

  addEventListener("mousedown", (e) => {
    start = { x: e.clientX, y: e.clientY };
    box.style.display = "block";
    hint.style.display = "none";
  });
  addEventListener("mousemove", (e) => {
    if (!start) return;
    const r = dragRect(e);
    box.style.left = `${r.x}px`;
    box.style.top = `${r.y}px`;
    box.style.width = `${r.w}px`;
    box.style.height = `${r.h}px`;
  });
  addEventListener("mouseup", (e) => {
    if (start) vp.pickerDone(dragRect(e));
    start = null;
  });
  addEventListener("keydown", (e) => {
    if (e.key === "Escape") vp.pickerCancel();
  });
}
