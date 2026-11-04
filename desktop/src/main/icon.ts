// The tray and app icons: port of Sources/VideoPrompt/MenuIcon.swift and scripts/make-app-icon.swift.
// Keep the coordinates matching those. Drawn here so the app ships no image files or SVG renderer.

type P = [number, number];

function bezier(path: P[], c1: P, c2: P, to: P) {
  const from = path[path.length - 1];
  for (let i = 1; i <= 16; i++) {
    const t = i / 16;
    const u = 1 - t;
    path.push([
      u * u * u * from[0] + 3 * u * u * t * c1[0] + 3 * u * t * t * c2[0] + t * t * t * to[0],
      u * u * u * from[1] + 3 * u * u * t * c1[1] + 3 * u * t * t * c2[1] + t * t * t * to[1],
    ]);
  }
}

/** A line from `a` to `bend` to `b`, with the bend rounded at `radius`. */
function corner(a: P, bend: P, b: P, radius: number): P[] {
  const toward = (from: P, to: P): P => {
    const d = Math.hypot(to[0] - from[0], to[1] - from[1]);
    return [from[0] + ((to[0] - from[0]) / d) * radius, from[1] + ((to[1] - from[1]) / d) * radius];
  };
  const path: P[] = [a, toward(bend, a)];
  const end = toward(bend, b);
  const start = path[1];
  // A quarter circle is close to a cubic with handles 0.55 of the way to the bend.
  const handle = (from: P): P => [from[0] + (bend[0] - from[0]) * 0.55, from[1] + (bend[1] - from[1]) * 0.55];
  bezier(path, handle(start), handle(end), end);
  path.push(b);
  return path;
}

function distanceToPath(x: number, y: number, path: P[]): number {
  let best = Infinity;
  for (let i = 1; i < path.length; i++) {
    const [ax, ay] = path[i - 1];
    const [bx, by] = path[i];
    const dx = bx - ax;
    const dy = by - ay;
    const len = dx * dx + dy * dy;
    const t = len ? Math.max(0, Math.min(1, ((x - ax) * dx + (y - ay) * dy) / len)) : 0;
    best = Math.min(best, Math.hypot(x - ax - t * dx, y - ay - t * dy));
  }
  return best;
}

type RGB = [number, number, number];

/** A BGRA premultiplied bitmap, drawn with a coverage function per layer. */
class Canvas {
  readonly px: Buffer;
  constructor(readonly pixels: number, readonly scale: number) {
    this.px = Buffer.alloc(pixels * pixels * 4);
  }

  /** `distance` is in grid units, negative inside the shape. */
  layer(distance: (x: number, y: number) => number, color: (x: number, y: number) => RGB) {
    for (let py = 0; py < this.pixels; py++) {
      for (let px = 0; px < this.pixels; px++) {
        const x = (px + 0.5) / this.scale;
        const y = (py + 0.5) / this.scale;
        const a = Math.max(0, Math.min(1, 0.5 - distance(x, y) * this.scale));
        if (a === 0) continue;
        const [r, g, b] = color(x, y);
        const i = (py * this.pixels + px) * 4;
        const keep = 1 - a;
        this.px[i] = Math.round(b * a + this.px[i] * keep);
        this.px[i + 1] = Math.round(g * a + this.px[i + 1] * keep);
        this.px[i + 2] = Math.round(r * a + this.px[i + 2] * keep);
        this.px[i + 3] = Math.round(255 * a + this.px[i + 3] * keep);
      }
    }
  }

  stroke(paths: P[][], width: number, color: RGB) {
    this.layer((x, y) => Math.min(...paths.map((p) => distanceToPath(x, y, p))) - width / 2, () => color);
  }
}

/**
 * The tray icon on its 18-point grid. macOS recolors a template image to suit the menu bar, but a
 * Plasma panel can be see-through, so nothing tells us what's behind it: the icon brings its own tile.
 */
export function trayBitmap(state: "idle" | "recording", pixels: number): Buffer {
  const c = new Canvas(pixels, pixels / 18);
  const foreground: RGB = [0xff, 0xff, 0xff];
  c.layer((x, y) => {
    const qx = Math.abs(x - 9) - 9 + 4;
    const qy = Math.abs(y - 9) - 9 + 4;
    return Math.hypot(Math.max(qx, 0), Math.max(qy, 0)) + Math.min(Math.max(qx, qy), 0) - 4;
  }, () => [0x1c, 0x1d, 0x22]);
  const corners = [
    corner([2.5, 6], [2.5, 2.5], [6, 2.5], 1),
    corner([12, 2.5], [15.5, 2.5], [15.5, 6], 1),
    corner([15.5, 12], [15.5, 15.5], [12, 15.5], 1),
    corner([6, 15.5], [2.5, 15.5], [2.5, 12], 1),
  ];
  c.stroke(corners, 1.5, foreground);
  if (state === "recording") {
    // The V becomes a red dot.
    c.layer((x, y) => Math.hypot(x - 9, y - 9) - 3.4, () => [0xd0, 0x31, 0x3a]);
  } else {
    const v: P[] = [[5.3, 6.1]];
    bezier(v, [5.9, 8], [7, 10.5], [8.3, 12.2]);
    bezier(v, [8.6, 12.6], [9.1, 12.6], [9.4, 12.2]);
    bezier(v, [10.8, 10.2], [11.7, 7.5], [13, 5]);
    c.stroke([v], 1.7, foreground);
  }
  return c.px;
}

/** The app icon on its 128-unit grid: a dark tile, light corners and the red V. */
export function appBitmap(pixels: number): Buffer {
  const c = new Canvas(pixels, pixels / 128);
  const tile = (x: number, y: number) => {
    const qx = Math.abs(x - 64) - 52 + 24;
    const qy = Math.abs(y - 64) - 52 + 24;
    return Math.hypot(Math.max(qx, 0), Math.max(qy, 0)) + Math.min(Math.max(qx, qy), 0) - 24;
  };
  const top: RGB = [0x2d, 0x2e, 0x35];
  const bottom: RGB = [0x13, 0x14, 0x18];
  c.layer(tile, (_x, y) => {
    const t = Math.max(0, Math.min(1, (y - 12) / 104));
    return [0, 1, 2].map((i) => top[i] + (bottom[i] - top[i]) * t) as RGB;
  });
  const corners = [
    corner([34, 52], [34, 34], [52, 34], 6),
    corner([76, 34], [94, 34], [94, 52], 6),
    corner([94, 76], [94, 94], [76, 94], 6),
    corner([52, 94], [34, 94], [34, 76], 6),
  ];
  c.stroke(corners, 6, [0xf3, 0xf3, 0xf5]);
  const v: P[] = [[43, 49]];
  bezier(v, [47, 61], [54, 75], [62, 84]);
  bezier(v, [64, 86.4], [66.6, 86.4], [68.4, 84]);
  bezier(v, [75, 74], [81, 58], [90, 41]);
  c.stroke([v], 8, [0xe5, 0x48, 0x4d]);
  return c.px;
}
