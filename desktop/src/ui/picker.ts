// Drag to choose the area to record, on Windows. Port of Sources/VideoPrompt/AreaPicker.swift: one of these
// covers each display, smaller than 80×80 doesn't count, and Esc cancels.
{
  const MIN = 80;
  const box = document.getElementById("box") as HTMLDivElement;
  let start: { x: number; y: number } | null = null;

  const rectTo = (e: PointerEvent) => ({
    x: Math.min(start!.x, e.clientX),
    y: Math.min(start!.y, e.clientY),
    w: Math.abs(e.clientX - start!.x),
    h: Math.abs(e.clientY - start!.y),
  });
  const show = (r: { x: number; y: number; w: number; h: number }) => {
    Object.assign(box.style, { display: "block", left: `${r.x}px`, top: `${r.y}px`, width: `${r.w}px`, height: `${r.h}px` });
    document.body.classList.add("dragging");
  };
  const reset = () => {
    start = null;
    box.style.display = "none";
    document.body.classList.remove("dragging");
  };

  addEventListener("pointerdown", (e) => {
    if (e.button !== 0) return;
    document.documentElement.setPointerCapture(e.pointerId);
    start = { x: e.clientX, y: e.clientY };
    show({ ...start, w: 0, h: 0 });
  });
  addEventListener("pointermove", (e) => {
    if (start) show(rectTo(e));
  });
  addEventListener("pointerup", (e) => {
    if (!start) return;
    const r = rectTo(e);
    reset();
    if (r.w >= MIN && r.h >= MIN) vp.pickerDone(r);
  });
  addEventListener("keydown", (e) => {
    if (e.key === "Escape") vp.pickerDone(null);
  });
}
