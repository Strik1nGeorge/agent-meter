import fs from 'node:fs';

// Readings of each quota window across its current instance, from its start to its reset, for the
// dashboard's burndown. Only changes are kept, as [time, remaining percent] pairs in time order, so a
// week of readings stays small. A window's instance is known by its reset time: a later reset time
// starts a new series, and late readings of an earlier instance are ignored. Stored in .data.
const SAME_RESET_MS = 3 * 60000;   // platforms may report the same reset a few seconds apart
const FINISHED_KEEP_MS = 3600000;  // a window that reset over an hour ago is no longer shown
const MAX_POINTS = 2000;

export const historyKey = (provider, window) => `${provider}|${window.id || window.name || ''}|${window.windowMinutes}`;

export class QuotaHistory {
  constructor(file) { this.file = file; this.series = new Map(); this.dirty = false; this.savedAt = 0; }

  load() {
    try {
      const raw = JSON.parse(fs.readFileSync(this.file, 'utf8'));
      for (const series of raw?.series || []) if (valid(series)) this.series.set(series.key, series);
    } catch {}
    return this;
  }

  // Every window of one platform's quota snapshot, at the time the platform reported it.
  record(provider, limits, time = limits?.collectedAt) {
    if (!limits || !Array.isArray(limits.windows) || !Number.isFinite(time)) return;
    for (const window of limits.windows) this.add(provider, window, time);
  }

  add(provider, window, time) {
    if (!window || !Number.isFinite(window.remainingPercent) || !Number.isFinite(window.resetsAt) || !(window.windowMinutes > 0)) return false;
    if (time < window.resetsAt - window.windowMinutes * 60000 || time > window.resetsAt) return false;
    const key = historyKey(provider, window);
    let series = this.series.get(key);
    if (series && Math.abs(series.resetsAt - window.resetsAt) > SAME_RESET_MS) {
      if (window.resetsAt < series.resetsAt) return false;
      series = null;
    }
    if (!series) this.series.set(key, series = { key, provider, windowMinutes: window.windowMinutes, resetsAt: window.resetsAt, points: [] });
    const value = Math.round(Math.max(0, Math.min(100, window.remainingPercent)) * 10) / 10;
    if (!insert(series.points, [Math.round(time), value])) return false;
    if (series.points.length > MAX_POINTS) series.points.splice(0, series.points.length - MAX_POINTS);
    this.dirty = true;
    return true;
  }

  // Readings of this window's current instance, oldest first.
  points(provider, window) {
    const series = window && this.series.get(historyKey(provider, window));
    return series && Number.isFinite(window.resetsAt) && Math.abs(series.resetsAt - window.resetsAt) <= SAME_RESET_MS ? series.points : [];
  }

  prune(now = Date.now()) {
    for (const [key, series] of this.series) if (series.resetsAt < now - FINISHED_KEEP_MS) { this.series.delete(key); this.dirty = true; }
  }

  // Through a temporary file, so an interrupted write never leaves a broken history behind.
  save() {
    if (!this.dirty || !this.file) return;
    try {
      fs.writeFileSync(this.file + '.tmp', JSON.stringify({ version: 1, series: [...this.series.values()] }));
      fs.renameSync(this.file + '.tmp', this.file);
      this.dirty = false;
      this.savedAt = Date.now();
    } catch {}
  }
}

function valid(series) {
  return series && typeof series.key === 'string' && Number.isFinite(series.resetsAt) && series.windowMinutes > 0 && Array.isArray(series.points)
    && series.points.every(p => Array.isArray(p) && Number.isFinite(p[0]) && Number.isFinite(p[1]));
}

// In time order, keeping only changes: a reading equal to the one before it adds nothing, and an
// earlier reading equal to the one after it makes the later one redundant.
function insert(points, point) {
  let i = points.length;
  while (i > 0 && points[i - 1][0] > point[0]) i--;
  if (i > 0 && points[i - 1][0] === point[0]) { if (points[i - 1][1] === point[1]) return false; points[i - 1] = point; }
  else if (i > 0 && points[i - 1][1] === point[1]) return false;
  else points.splice(i, 0, point);
  for (let j = points.length - 1; j > 0; j--) if (points[j][1] === points[j - 1][1]) points.splice(j, 1);
  return true;
}
