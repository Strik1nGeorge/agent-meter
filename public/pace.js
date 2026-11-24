import { quotaDisplay } from './quota-display.js';

// How a quota window is being used. `expected` is the share that even use across the window would leave
// right now (the tick on rings and bars). The forecast extends the window's average rate so far: from
// 100% at the window's start through the current reading, until it either reaches 0% ("runs-out", with
// the time) or the reset comes first ("lasts", with the share left at the reset). Too early in a window
// ("early": under a tenth of the window, so a week waits for most of a day and night) or already used up
// ("empty") gives no forecast. desktop/Models.cs (Pace.Of) mirrors this.
export const MIN_ELAPSED_MS = 10 * 60000, MIN_ELAPSED_SHARE = 0.1;

export function quotaPace(window, windows, now = Date.now()) {
  if (!window || !Number.isFinite(window.resetsAt) || !(window.windowMinutes > 0) || window.resetsAt <= now) return null;
  const shown = quotaDisplay(window, windows || [], now);
  if (shown.weeklyBlocked || shown.expired || shown.remainingPercent == null) return null;
  const length = window.windowMinutes * 60000, start = window.resetsAt - length;
  const pace = { start, expected: Math.max(0, Math.min(100, (window.resetsAt - now) / length * 100)), state: 'early', runsOutAt: null, leftAtReset: null };
  const remaining = shown.remainingPercent, used = 100 - remaining, elapsed = Math.max(0, now - start);
  if (remaining <= 0) pace.state = 'empty';
  else if (used <= 0) { pace.state = 'lasts'; pace.leftAtReset = remaining; }
  else if (elapsed >= Math.max(MIN_ELAPSED_MS, length * MIN_ELAPSED_SHARE)) {
    const rate = used / elapsed, runsOutAt = now + remaining / rate;
    if (runsOutAt < window.resetsAt) { pace.state = 'runs-out'; pace.runsOutAt = Math.round(runsOutAt); }
    else { pace.state = 'lasts'; pace.leftAtReset = Math.max(0, remaining - rate * (window.resetsAt - now)); }
  }
  return pace;
}
