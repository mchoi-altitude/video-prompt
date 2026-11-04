// Finding a region chosen in the system's dialog, which doesn't say where it is. The overlay is in
// the capture, so it paints stripes that encode screen position, one bit per frame, and the first and
// last pixels the capture sees give the region's place. Capture alters colors, so the stripes are
// neutral and only read as light or dark. They're Gray code, so neighboring pixels differ by one bit.

export type RGB = [number, number, number];

/** One frame of stripes. `bit` of the position along `axis`, drawn with these two brightness levels. */
export type Step = { axis: "x" | "y"; bit: number; dark: number; light: number };

// Each frame's levels differ from the last two frames', so a frame from before it reached the
// capture is never read as this one. Far enough apart to survive small changes in the capture.
const LEVELS = [[0, 255], [40, 215], [80, 175]];
const TOLERANCE = 18;

const bitsFor = (size: number) => Math.ceil(Math.log2(size));

export function patternSteps(screenW: number, screenH: number): Step[] {
  const bits = (axis: "x" | "y", size: number) => Array.from({ length: bitsFor(size) }, (_, i) => ({ axis, bit: bitsFor(size) - 1 - i }));
  return [...bits("x", screenW), ...bits("y", screenH)].map((s, i) => ({ ...s, dark: LEVELS[i % 3][0], light: LEVELS[i % 3][1] }));
}

/** What a step paints at a position along its axis. Mirrored by drawPattern in ui/overlay.ts. */
export function stepLevel(step: Step, position: number): number {
  const gray = position ^ (position >> 1);
  return (gray >> step.bit) & 1 ? step.light : step.dark;
}

/** What the capture saw at its two test pixels. */
export type Sample = { width: number; height: number; first: RGB; last: RGB };

/** Test pixels sit this far in from each edge, clear of any rounding at the region's border. */
export const SAMPLE_INSET = 4;

const brightness = (c: RGB) => (c[0] + c[1] + c[2]) / 3;

/** Whether both test pixels show this step's own levels, in a neutral color. */
export function showsStep(sample: Sample, step: Step): boolean {
  return [sample.first, sample.last].every((c) => {
    const v = brightness(c);
    return Math.max(...c) - Math.min(...c) <= 2 * TOLERANCE && (Math.abs(v - step.dark) <= TOLERANCE || Math.abs(v - step.light) <= TOLERANCE);
  });
}

function fromGray(gray: number): number {
  let n = 0;
  for (let g = gray; g; g >>= 1) n ^= g;
  return n;
}

/**
 * The region's top-left in screen pixels, or null unless the two test pixels are exactly as far
 * apart as the capture's size says. A wrong position is worse than none, so this is strict.
 */
export function locate(steps: Step[], samples: Sample[], screenW: number, screenH: number): { x: number; y: number } | null {
  const read = (axis: "x" | "y", pixel: "first" | "last") => {
    let gray = 0;
    steps.forEach((step, i) => {
      if (step.axis === axis && brightness(samples[i][pixel]) > (step.dark + step.light) / 2) gray |= 1 << step.bit;
    });
    return fromGray(gray);
  };
  const { width, height } = samples[0];
  if (samples.some((s) => s.width !== width || s.height !== height)) return null;
  const x = read("x", "first") - SAMPLE_INSET;
  const y = read("y", "first") - SAMPLE_INSET;
  const spanW = width - 1 - 2 * SAMPLE_INSET;
  const spanH = height - 1 - 2 * SAMPLE_INSET;
  if (Math.abs(read("x", "last") - SAMPLE_INSET - spanW - x) > 1 || Math.abs(read("y", "last") - SAMPLE_INSET - spanH - y) > 1) return null;
  if (x < 0 || y < 0 || x + width > screenW || y + height > screenH) return null;
  return { x, y };
}
