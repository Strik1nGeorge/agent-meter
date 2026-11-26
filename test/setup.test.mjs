import test from 'node:test';
import assert from 'node:assert/strict';
import { claudeSetupCommand } from '../lib/setup.mjs';
import { macCodexCandidates } from '../lib/codex-rpc.mjs';

test('the Claude setup command is PowerShell on Windows and POSIX shell elsewhere, quoted for each', () => {
  assert.equal(claudeSetupCommand('win32', 'C:\\Program Files\\nodejs\\node.exe', "C:\\Users\\O'Neil\\agent-meter\\scripts\\connect-claude.mjs"),
    "& 'C:\\Program Files\\nodejs\\node.exe' 'C:\\Users\\O''Neil\\agent-meter\\scripts\\connect-claude.mjs'");
  assert.equal(claudeSetupCommand('darwin', '/opt/homebrew/bin/node', "/Users/o'neil/agent meter/scripts/connect-claude.mjs"),
    "'/opt/homebrew/bin/node' '/Users/o'\\''neil/agent meter/scripts/connect-claude.mjs'");
  assert.equal(claudeSetupCommand('linux', '/usr/bin/node', '/home/a/x.mjs'), "'/usr/bin/node' '/home/a/x.mjs'");
});

test('on a Mac Codex is looked for inside its app first, then where Homebrew and npm install it', () => {
  assert.deepEqual(macCodexCandidates('/Users/a'), [
    '/Applications/Codex.app/Contents/Resources/codex', '/Applications/ChatGPT.app/Contents/Resources/codex',
    '/Users/a/Applications/Codex.app/Contents/Resources/codex', '/Users/a/Applications/ChatGPT.app/Contents/Resources/codex',
    '/opt/homebrew/bin/codex', '/usr/local/bin/codex', '/Users/a/.local/bin/codex',
  ]);
});
