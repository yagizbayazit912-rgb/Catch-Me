"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.acceptedDelta = acceptedDelta;
exports.effectiveLevel = effectiveLevel;
/** Keep fractional seconds: flooring every heartbeat loses time. */
function acceptedDelta(now, last, maxGap = 35) {
    if (last === undefined)
        return 0;
    const seconds = (now - last) / 1000;
    return seconds > 0 && seconds <= maxGap ? seconds : 0;
}
function effectiveLevel(target, from, readyAt, now) {
    const level = readyAt !== undefined && readyAt > now ? (from ?? target - 1) : target;
    return Math.max(0, Math.min(5, level));
}
//# sourceMappingURL=timing.js.map