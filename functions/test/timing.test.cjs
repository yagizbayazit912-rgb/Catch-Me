const test = require('node:test');
const assert = require('node:assert/strict');
const { acceptedDelta, effectiveLevel } = require(process.env.TIMING_TEST_SOURCE || '../lib/timing.js');

test('fractional heartbeats do not lose seconds', () => {
  const stamps = [100000, 104999, 109998, 114997, 119996, 124995, 130000];
  const elapsed = stamps.slice(1).reduce((sum, stamp, i) => sum + acceptedDelta(stamp, stamps[i]), 0);
  assert.ok(Math.abs(elapsed - 30) < 1e-10);
});
test('first sample, stale sample and backwards time earn nothing', () => {
  assert.equal(acceptedDelta(100000, undefined), 0);
  assert.equal(acceptedDelta(136000, 100000), 0);
  assert.equal(acceptedDelta(99000, 100000), 0);
});
test('construction uses previous level until the exact deadline', () => {
  assert.equal(effectiveLevel(2, 1, 300000, 299999), 1);
  assert.equal(effectiveLevel(2, 1, 300000, 300000), 2);
  assert.equal(effectiveLevel(2, 1, undefined, 300001), 2);
});
test('legacy construction fallback and boundary levels', () => {
  assert.equal(effectiveLevel(1, undefined, 5000, 4999), 0);
  assert.equal(effectiveLevel(5, 4, 5000, 5000), 5);
  assert.equal(effectiveLevel(9, undefined, undefined, 5000), 5);
});
