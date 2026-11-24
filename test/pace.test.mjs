import test from 'node:test';
import assert from 'node:assert/strict';
import { quotaPace } from '../public/pace.js';

const now = Date.parse('2026-11-24T12:00:00Z');
const hour = 3600000, day = 24 * hour;
const window = (remaining, resetIn, minutes = 300, extra = {}) => ({ windowMinutes: minutes, remainingPercent: remaining, resetsAt: now + resetIn, ...extra });

test('the tick marks what even use would leave right now', () => {
  assert.equal(quotaPace(window(62, 2.6 * hour), [], now).expected.toFixed(2), '52.00');
  assert.equal(quotaPace(window(58, 3.4 * day, 10080), [], now).expected.toFixed(2), (3.4 / 7 * 100).toFixed(2));
  assert.equal(quotaPace(window(62, 2.6 * hour), [], now).start, now + 2.6 * hour - 5 * hour);
});

test('the window average so far either runs out before the reset or lasts with a share left', () => {
  // Three hours in with 76% used: 24% lasts about 57 minutes, an hour before the reset.
  const fast = quotaPace(window(24, 2 * hour), [], now);
  assert.equal(fast.state, 'runs-out');
  assert.ok(Math.abs(fast.runsOutAt - (now + 24 / (76 / (3 * hour)))) <= 1);
  assert.equal(fast.leftAtReset, null);
  // 2.4 hours in with 38% used: about 21% is left when the window resets 2.6 hours from now.
  const steady = quotaPace(window(62, 2.6 * hour), [], now);
  assert.equal(steady.state, 'lasts');
  assert.equal(Math.round(steady.leftAtReset), 21);
  assert.equal(steady.runsOutAt, null);
});

test('no forecast this early in a window or once it is used up; an untouched window lasts in full', () => {
  assert.equal(quotaPace(window(97, 5 * hour - 5 * 60000), [], now).state, 'early');
  assert.equal(quotaPace(window(80, 5 * hour - 25 * 60000), [], now).state, 'early');
  assert.equal(quotaPace(window(80, 5 * hour - 35 * 60000), [], now).state, 'runs-out');
  assert.equal(quotaPace(window(70, 7 * day - 13 * hour, 10080), [], now).state, 'early', 'a week waits for most of a day and night');
  assert.equal(quotaPace(window(0, hour), [], now).state, 'empty');
  assert.deepEqual([quotaPace(window(100, hour), [], now).state, quotaPace(window(100, hour), [], now).leftAtReset], ['lasts', 100]);
});

test('no pace without a reset time, a length or a reading, after the reset, or while the week blocks the window', () => {
  for (const w of [window(50, hour, 300, { resetsAt: null }), window(50, hour, null), window(null, hour), window(50, 0), window(50, -hour)]) assert.equal(quotaPace(w, [], now), null);
  const short = window(80, hour), week = window(0, day, 10080);
  assert.equal(quotaPace(short, [short, week], now), null);
  assert.equal(quotaPace(week, [short, week], now).state, 'empty');
  assert.equal(quotaPace(null, [], now), null);
});
