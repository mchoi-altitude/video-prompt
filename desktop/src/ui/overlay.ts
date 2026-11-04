// Same timing and color as Sources/VPApp/Drawing.swift and OverlayWindows.swift.
{
  const HOLD_MS = 3000;
  const FADE_MS = 500;
  const RED = "229, 72, 77";

  type Stroke = { tool: Tool; points: number[][]; t0: number; endedAt?: number };

  const canvas = document.getElementById("c") as HTMLCanvasElement;
  const count = document.getElementById("count") as HTMLDivElement;
  const ctx = canvas.getContext("2d")!;
  let strokes: Stroke[] = [];
  let current: Stroke | null = null;
  let drawing = false;
  let animating = false;
  let tool: Tool = "pen";
  let fades = true;
  let origin = { x: 0, y: 0 };
  let region: { x: number; y: number; w: number; h: number } | null = null;

  const opacity = (s: Stroke, now: number) => {
    if (!fades || s.endedAt === undefined) return 1;
    const age = now - s.endedAt;
    if (age <= HOLD_MS) return 1;
    return Math.max(0, 1 - (age - HOLD_MS) / FADE_MS);
  };

  const drawArrow = ([x0, y0]: number[], [x1, y1]: number[]) => {
    const angle = Math.atan2(y1 - y0, x1 - x0);
    ctx.moveTo(x0, y0);
    ctx.lineTo(x1, y1);
    for (const side of [-1, 1]) {
      ctx.moveTo(x1, y1);
      ctx.lineTo(x1 - 16 * Math.cos(angle + (side * Math.PI) / 7), y1 - 16 * Math.sin(angle + (side * Math.PI) / 7));
    }
  };

  const redraw = () => {
    const now = Date.now();
    strokes = strokes.filter((s) => opacity(s, now) > 0);
    ctx.setTransform(devicePixelRatio, 0, 0, devicePixelRatio, 0, 0);
    ctx.clearRect(0, 0, innerWidth, innerHeight);
    if (region) {
      // Just outside the region, so it marks the edge on screen without being in the video.
      ctx.lineWidth = 3;
      ctx.strokeStyle = `rgb(${RED})`;
      ctx.strokeRect(region.x - origin.x - 2, region.y - origin.y - 2, region.w + 4, region.h + 4);
    }
    ctx.lineWidth = 4;
    ctx.lineCap = "round";
    ctx.lineJoin = "round";
    for (const s of strokes) {
      ctx.strokeStyle = `rgba(${RED}, ${opacity(s, now)})`;
      ctx.beginPath();
      const first = s.points[0];
      const last = s.points[s.points.length - 1];
      if (s.tool === "arrow") drawArrow(first, last);
      else if (s.tool === "box") ctx.rect(first[0], first[1], last[0] - first[0], last[1] - first[1]);
      else s.points.forEach(([x, y], i) => (i ? ctx.lineTo(x, y) : ctx.moveTo(x, y)));
      ctx.stroke();
    }
  };

  // Runs only while marks are on screen, so an empty overlay costs nothing.
  const animate = () => {
    redraw();
    animating = strokes.length > 0;
    if (animating) requestAnimationFrame(animate);
  };

  type Pattern = { axis: "x" | "y"; bit: number; dark: number; light: number };
  let pattern: Pattern | null = null;

  // Pixels are written directly so levels land exactly as painted. Mirrors stepLevel in core/locate.ts.
  const drawPattern = ({ axis, bit, dark, light }: Pattern) => {
    const W = canvas.width;
    const H = canvas.height;
    const image = ctx.createImageData(W, H);
    const px = new Uint32Array(image.data.buffer);
    const color = (position: number) => {
      const level = ((position ^ (position >> 1)) >> bit) & 1 ? light : dark;
      return 0xff000000 | (level * 0x010101);
    };
    if (axis === "x") {
      const row = Uint32Array.from({ length: W }, (_, x) => color(x));
      for (let y = 0; y < H; y++) px.set(row, y * W);
    } else {
      for (let y = 0; y < H; y++) px.fill(color(y), y * W, (y + 1) * W);
    }
    ctx.putImageData(image, 0, 0);
  };

  const resize = () => {
    canvas.width = innerWidth * devicePixelRatio;
    canvas.height = innerHeight * devicePixelRatio;
    // Resizing wipes the canvas, and the window reaches full size only after it's shown.
    if (pattern) drawPattern(pattern);
    else redraw();
  };
  addEventListener("resize", resize);
  resize();

  vp.onInit((o) => {
    origin = o.origin;
    fades = o.fades;
  });
  vp.onRegion((r) => {
    region = r;
    redraw();
  });
  vp.onDrawChanged((on) => {
    drawing = on;
    document.body.style.cursor = on ? "crosshair" : "default";
  });
  vp.onSetTool((t) => (tool = t));
  vp.onUndo(() => {
    strokes.pop();
    redraw();
  });
  vp.onClear(() => {
    strokes = [];
    current = null;
    redraw();
  });
  vp.onCountdown(() => {
    let n = 3;
    count.style.display = "flex";
    count.textContent = String(n);
    const tick = setInterval(() => {
      n -= 1;
      if (n > 0) {
        count.textContent = String(n);
        return;
      }
      clearInterval(tick);
      count.style.display = "none";
      // Let the number leave the screen before the first frame.
      requestAnimationFrame(() => requestAnimationFrame(() => vp.countdownDone()));
    }, 1000);
  });

  const paintPattern = async (step: Pattern) => {
    pattern = step;
    drawPattern(step);
    await new Promise((resolve) => requestAnimationFrame(resolve));
  };
  const clearPattern = () => {
    pattern = null;
    redraw();
  };
  Object.assign(window, { paintPattern, clearPattern });

  canvas.addEventListener("pointerdown", (e) => {
    if (!drawing) return;
    canvas.setPointerCapture(e.pointerId);
    vp.strokeActive(true);
    current = { tool, points: [[e.clientX, e.clientY]], t0: Date.now() };
    strokes.push(current);
    if (!animating) animate();
  });
  canvas.addEventListener("pointermove", (e) => {
    if (!current) {
      if (drawing) vp.overlayPointer(e.clientX, e.clientY);
      return;
    }
    // Arrow and box keep only start and end, like the Mac.
    if (current.tool === "pen") current.points.push([e.clientX, e.clientY]);
    else current.points = [current.points[0], [e.clientX, e.clientY]];
  });
  canvas.addEventListener("pointerup", () => {
    vp.strokeActive(false);
    if (!current) return;
    const s = current;
    current = null;
    // A click that never moved isn't a mark.
    if (s.points.length < 2) {
      strokes = strokes.filter((x) => x !== s);
      return;
    }
    s.endedAt = Date.now();
    vp.stroke({ t0: s.t0, t1: s.endedAt, tool: s.tool, points: s.points.map(([x, y]) => ({ x: x + origin.x, y: y + origin.y })) });
  });
}
