// Finding a region chosen in the system's dialog, which doesn't say where it is. The overlay is in
// the capture, so it paints a code for screen position at very low opacity, one bit of x and one of
// y per frame. It's too faint to read directly, so each frame at the region's first and last pixels
// is compared with how those pixels looked just before: the difference gives the code.

export type RGB = [number, number, number];

/** One frame: bit `bit` of both x and y. */
export type Step = { bit: number };

/** The code's opacity, out of 255. Low enough that the screen stays clearly visible through it. */
export const PATTERN_ALPHA = 9;
const ALPHA = PATTERN_ALPHA / 255;
/** How much each of the four code levels adds to a pixel's brightness, at this opacity. */
const LEVEL_STEP = PATTERN_ALPHA / 3;
/** A reading further than this from any level isn't the code: something else changed the pixel. */
const TOLERANCE = 1.3;

export function patternSteps(screenW: number, screenH: number): Step[] {
  const bits = Math.ceil(Math.log2(Math.max(screenW, screenH)));
  return Array.from({ length: bits }, (_, i) => ({ bit: bits - 1 - i }));
}

/** The code level (0 to 3) a step paints at a screen pixel. Mirrored by drawPattern in ui/overlay.ts. */
export function stepLevel(step: Step, x: number, y: number): number {
  return ((x >> step.bit) & 1) * 2 + ((y >> step.bit) & 1);
}

/** What a pixel of brightness `under` becomes beneath code level `level`. */
export function blended(under: number, level: number): number {
  return under * (1 - ALPHA) + level * LEVEL_STEP;
}

/** What the capture saw at its two test pixels. */
export type Sample = { width: number; height: number; first: RGB; last: RGB };

/** Test pixels sit this far in from each edge, clear of any rounding at the region's border. */
export const SAMPLE_INSET = 4;

const brightness = (c: RGB) => (c[0] + c[1] + c[2]) / 3;

function levelOf(seen: RGB, before: RGB): number | null {
  const added = brightness(seen) - brightness(before) * (1 - ALPHA);
  const level = Math.round(added / LEVEL_STEP);
  if (level < 0 || level > 3 || Math.abs(added - level * LEVEL_STEP) > TOLERANCE) return null;
  return level;
}

const unchanged = (a: RGB, b: RGB) => Math.abs(brightness(a) - brightness(b)) <= 2;

/**
 * The region's top-left in screen pixels, or null if the screen changed at the test pixels during
 * the measurement, or they aren't exactly as far apart as the capture's size says. A wrong position
 * is worse than none, so this is strict.
 */
export function locate(steps: Step[], before: Sample, samples: Sample[], after: Sample, screenW: number, screenH: number): { x: number; y: number } | null {
  if (!unchanged(before.first, after.first) || !unchanged(before.last, after.last)) return null;
  const { width, height } = before;
  if (samples.some((s) => s.width !== width || s.height !== height)) return null;
  const read = (pixel: "first" | "last") => {
    let x = 0;
    let y = 0;
    for (let i = 0; i < steps.length; i++) {
      const level = levelOf(samples[i][pixel], before[pixel]);
      if (level === null) return null;
      x |= (level >> 1) << steps[i].bit;
      y |= (level & 1) << steps[i].bit;
    }
    return { x, y };
  };
  const a = read("first");
  const b = read("last");
  if (!a || !b) return null;
  const x = a.x - SAMPLE_INSET;
  const y = a.y - SAMPLE_INSET;
  if (Math.abs(b.x - a.x - (width - 1 - 2 * SAMPLE_INSET)) > 1 || Math.abs(b.y - a.y - (height - 1 - 2 * SAMPLE_INSET)) > 1) return null;
  if (x < 0 || y < 0 || x + width > screenW || y + height > screenH) return null;
  return { x, y };
}
