/** Keep fractional seconds: flooring every heartbeat loses time. */
export function acceptedDelta(now: number, last: number | undefined, maxGap = 35): number {
  if (last === undefined) return 0;
  const seconds = (now - last) / 1000;
  return seconds > 0 && seconds <= maxGap ? seconds : 0;
}

export function effectiveLevel(target: number, from: number | undefined, readyAt: number | undefined, now: number): number {
  const level = readyAt !== undefined && readyAt > now ? (from ?? target - 1) : target;
  return Math.max(0, Math.min(5, level));
}
