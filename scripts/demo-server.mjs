// Throwaway server for README screenshots: serves the real dashboard files from the project's
// public/ folder, but answers /api/snapshot and /api/quotas with made-up demo data (no real sessions,
// projects or quotas). /light, /dark, /light-en, /dark-zh … preset the theme and language.
// Usage: node scripts/demo-server.mjs [project-root] [port]
import http from 'node:http';
import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = process.argv[2] || path.join(path.dirname(fileURLToPath(import.meta.url)), '..');
const port = Number(process.argv[3] || 4400);
const types = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.css': 'text/css; charset=utf-8', '.svg': 'image/svg+xml' };
const hour = 3600000, day = 24 * hour;

function rng(seed) { return () => { seed = (seed * 1664525 + 1013904223) % 4294967296; return seed / 4294967296; }; }

// Readings stepping down from a full window to the current share, at whole percents like the platforms report.
function readings(minutes, remaining, resetIn, seed, now) {
  const start = now + resetIn - minutes * 60000, random = rng(seed);
  const count = minutes <= 300 ? 12 : 26;
  const times = Array.from({ length: count }, () => start + (0.04 + random() * 0.93) * (now - start)).sort((a, b) => a - b);
  const weights = times.map(() => 0.25 + random()), total = weights.reduce((a, b) => a + b, 0);
  const points = [];
  let used = 0, last = 100;
  times.forEach((time, i) => {
    used += weights[i] / total * (100 - remaining);
    const value = i === count - 1 ? remaining : Math.round(100 - used);
    if (value < last) { points.push([Math.round(time), value]); last = value; }
  });
  return points;
}

function snapshot() {
  const now = Date.now();
  const random = rng(7);
  const sessions = [
    ['codex', 'Refactor billing retry logic', 'billing-service', 'gpt-6-astra', 'recent', 'session', 54, 1.0],
    ['claude', 'Design the onboarding flow', 'mobile-app', 'claude-opus-5-5', 'recent', 'session', 38, 1.3],
    ['codex', 'Add dark mode to settings', 'web-app', 'gpt-6.1-sol', 'idle', 'session', 71, 0.8],
    ['claude', 'Investigate memory leak in worker', 'jobs-worker', 'claude-opus-5-5', 'idle', 'session', 22, 0.9],
    ['codex', 'Fix flaky upload test', 'web-app', 'gpt-6-astra', 'idle', 'subagent', 12, 0.35],
    ['claude', 'Write release notes for v2.3', 'docs', 'claude-sonnet-5-5', 'idle', 'session', null, 0.4],
    ['codex', 'Migrate auth to OAuth 2.1', 'auth-gateway', 'gpt-6.1-sol', 'idle', 'session', 47, 0.7],
    ['claude', 'Explore: find uses of the legacy API', 'mobile-app', 'claude-sonnet-5-5', 'idle', 'subagent', null, 0.25],
  ].map(([provider, name, project, model, activity, kind, context, weight], index) => {
    const records = [];
    for (let d = 6; d >= 0; d--) {
      const busy = 0.4 + 0.6 * Math.abs(Math.sin((d + index) * 1.3));
      const count = Math.round((2 + random() * 5) * busy * weight);
      for (let i = 0; i < count; i++) {
        const input = Math.round((90000 + random() * 160000) * weight), output = Math.round(input * (0.012 + random() * 0.02));
        // Place each day's records inside that calendar day in America/New_York (the chart's time zone).
        const parts = Object.fromEntries(new Intl.DateTimeFormat('en-US', { timeZone: 'America/New_York', hour: 'numeric', minute: 'numeric', hourCycle: 'h23' }).formatToParts(now).map(p => [p.type, p.value]));
        const startOfToday = now - (Number(parts.hour) * 60 + Number(parts.minute)) * 60000;
        const time = d === 0 ? startOfToday + random() * (now - startOfToday) : startOfToday - d * day + (8 + random() * 12) * hour;
        if (time > now) continue;
        records.push({ id: `${provider}-${index}-${d}-${i}`, time, model, input, output, cached: Math.round(input * (0.9 + random() * 0.08)), cacheWrite: Math.round(input * 0.02), reasoning: Math.round(output * 0.4), total: input + output });
      }
    }
    records.sort((a, b) => a.time - b.time);
    return { provider, id: `demo-${provider}-${index}`, parentId: kind === 'subagent' ? `demo-${provider}-0` : null, kind, model, updatedAt: activity === 'recent' ? now - 40000 : records.at(-1).time, startedAt: records[0].time, context: context == null ? null : { percent: context }, guardian: false, name, project, activity, records };
  });
  // Codex lasts on both windows; Claude's 5 hours are going fast enough to run out an hour before their reset.
  const quota = (id, name, minutes, remaining, resetIn, seed) => ({ ...(id ? { id } : {}), name, usedPercent: 100 - remaining, remainingPercent: remaining, windowMinutes: minutes, resetsAt: now + resetIn, history: readings(minutes, remaining, resetIn, seed, now) });
  return {
    collectedAt: now - 2000, loading: false, timeZone: 'America/New_York', refreshSeconds: 5,
    providers: [
      { id: 'codex', name: 'Codex', connected: true, fileCount: 42, error: null, bridgeConnected: false, quotaStatus: null, quotaMessage: null, quotaError: null,
        limits: { windows: [quota(null, '5 小时', 300, 62, 2.6 * hour, 11), quota(null, '7 天', 10080, 58, 3.4 * day, 12)], plan: 'plus', collectedAt: now - 40000, source: 'Codex 官方额度接口', staleAfterMs: 180000 } },
      { id: 'claude', name: 'Claude Code', connected: true, fileCount: 37, error: null, bridgeConnected: false, quotaStatus: 'available', quotaMessage: null, quotaError: null,
        limits: { windows: [quota('five_hour', '5 小时', 300, 24, 2 * hour, 21), quota('seven_day', '7 天', 10080, 73, 2.3 * day, 22), quota('seven_day_opus', 'Opus · 7 天', 10080, 86, 2.3 * day, 23)], plan: null, collectedAt: now - 90000, source: 'Claude 桌面账户额度', staleAfterMs: 600000 } },
    ],
    sessions,
  };
}

http.createServer(async (req, res) => {
  const url = new URL(req.url, `http://127.0.0.1:${port}`);
  if (url.pathname === '/api/snapshot') { res.setHeader('Content-Type', 'application/json'); res.end(JSON.stringify(snapshot())); return; }
  if (url.pathname === '/api/quotas') {
    // Demo activity for the widget's pets and hover cards: Claude at work in two sessions, Codex resting.
    const data = snapshot(), now = Date.now();
    data.providers = data.providers.map(p => ({ ...p, activity: p.id === 'claude'
      ? { working: true, activeSessions: 2, todayTokens: 4300000, todayRequests: 38, lastActiveAt: now - 20000, model: 'claude-opus-5-5', effort: 'max' }
      : { working: false, activeSessions: 0, todayTokens: 2860000, todayRequests: 57, lastActiveAt: now - 12 * 60000, model: 'gpt-6.1-sol', effort: 'high' } }));
    delete data.sessions;
    res.setHeader('Content-Type', 'application/json'); res.end(JSON.stringify(data)); return;
  }
  const preset = /^\/(light|dark)(?:-(en|zh))?$/.exec(url.pathname);
  const theme = preset?.[1], lang = preset?.[2];
  const file = theme || url.pathname === '/' ? 'index.html' : url.pathname.slice(1);
  try {
    let body = await fs.readFile(path.join(root, 'public', path.basename(file)));
    if (theme) body = Buffer.from(body.toString('utf8').replace('<head>', `<head><script>localStorage.setItem('agent-hud-theme','${theme}');${lang ? `localStorage.setItem('agent-hud-lang','${lang}');` : ''}</script>`));
    res.setHeader('Content-Type', types[path.extname(file)] || 'application/octet-stream');
    res.end(body);
  } catch { res.writeHead(404); res.end(); }
}).listen(port, '127.0.0.1', () => console.log(`demo dashboard on http://127.0.0.1:${port}`));
