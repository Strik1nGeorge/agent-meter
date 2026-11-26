// The command the dashboard's setup dialog shows for connecting the Claude Code CLI status line:
// PowerShell syntax on Windows, POSIX shell syntax on macOS and Linux. Paths are quoted for that shell.
export function claudeSetupCommand(platform, node, script) {
  if (platform === 'win32') {
    const quote = text => `'${text.replaceAll("'", "''")}'`;
    return `& ${quote(node)} ${quote(script)}`;
  }
  const quote = text => `'${text.replaceAll("'", "'\\''")}'`;
  return `${quote(node)} ${quote(script)}`;
}
