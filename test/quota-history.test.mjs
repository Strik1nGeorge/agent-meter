import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { QuotaHistory } from '../lib/quota-history.mjs';

const now = Date.parse('2026-11-24T12:00:00Z');
const hour = 3600000, minute = 60000;
const five = (remaining, resetsAt = now + 2 * hour) => ({ name: '5 小时', windowMinutes: 300, remainingPercent: remaining, resetsAt });
const week = remaining => ({ name: '7 天', windowMinutes: 10080, remainingPercent: remaining, resetsAt: now + 24 * hour });
const limits = (time, ...windows) => ({ collectedAt: time, windows });

test('history keeps only changes in time order, even when older log readings arrive after live ones', () => {
  const history = new QuotaHistory(null);
  history.record('codex', limits(now - 50 * minute, five(90)));
  history.record('codex', limits(now - 40 * minute, five(90)));
  history.record('codex', limits(now - 10 * minute, five(70)));
  history.record('codex', limits(now - 30 * minute, five(80)));
  history.record('codex', limits(now - 20 * minute, five(70)));
  assert.deepEqual(history.points('codex', five(70)), [[now - 50 * minute, 90], [now - 30 * minute, 80], [now - 20 * minute, 70]]);
  assert.equal(history.add('codex', five(70), now - 20 * minute), false);
});

test('a later reset starts a new series; late readings of the earlier window are ignored', () => {
  const history = new QuotaHistory(null);
  history.record('claude', limits(now - hour, five(40)));
  const next = now + 5 * hour;
  history.record('claude', limits(now + 10 * minute, five(95, next)));
  history.record('claude', limits(now - 30 * minute, five(35)));
  assert.deepEqual(history.points('claude', five(95, next)), [[now + 10 * minute, 95]]);
  assert.deepEqual(history.points('claude', five(35)), []);
  assert.equal(history.points('claude', five(95, next + 20000)).length, 1, 'a reset reported seconds apart is the same window');
});

test('readings outside their window or without a reset time or percentage are skipped, and platforms stay apart', () => {
  const history = new QuotaHistory(null);
  history.record('codex', limits(now - 6 * hour, five(50)));
  history.record('codex', limits(now, { ...five(50), resetsAt: null }));
  history.record('codex', limits(now, five(null)));
  history.record('codex', { windows: [five(50)] });
  history.record('claude', limits(now, five(60)));
  assert.deepEqual(history.points('codex', five(60)), []);
  assert.deepEqual(history.points('claude', five(60)), [[now, 60]]);
});

test('history survives a restart, drops windows that reset over an hour ago and ignores a broken file', async t => {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'agent-meter-history-'));
  t.after(() => fs.rm(root, { recursive: true, force: true }));
  const file = path.join(root, 'quota-history.json');
  const history = new QuotaHistory(file);
  history.record('codex', limits(now - hour, five(80), week(60)));
  history.save();
  assert.equal(history.dirty, false);
  const again = new QuotaHistory(file).load();
  assert.deepEqual(again.points('codex', five(80)), [[now - hour, 80]]);
  again.prune(now + 3 * hour + 1);
  assert.deepEqual(again.points('codex', five(80)), []);
  assert.deepEqual(again.points('codex', week(60)), [[now - hour, 60]]);
  await fs.writeFile(file, '{broken');
  assert.equal(new QuotaHistory(file).load().series.size, 0);
});
