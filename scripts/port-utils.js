const { execSync } = require('child_process');

/**
 * Find all process IDs listening on a specific TCP port and kill them with their child trees.
 */
function freePort(port) {
  if (!port) return;
  const targetPort = parseInt(port, 10);
  if (isNaN(targetPort)) return;

  const pidsToKill = new Set();

  if (process.platform === 'win32') {
    // 1. Try netstat with regex matching :port
    try {
      const stdout = execSync('netstat -ano', { encoding: 'utf-8' });
      const lines = stdout.split('\n');
      const portRegex = new RegExp(`:${targetPort}\\s+.*LISTENING\\s+(\\d+)`, 'i');

      for (const line of lines) {
        const match = line.match(portRegex);
        if (match && match[1]) {
          const pid = match[1].trim();
          if (pid !== '0' && pid !== String(process.pid)) {
            pidsToKill.add(pid);
          }
        }
      }
    } catch (_) {}

    // 2. Try PowerShell Get-NetTCPConnection as fallback
    try {
      const psCmd = `powershell -NoProfile -Command "Get-NetTCPConnection -LocalPort ${targetPort} -ErrorAction SilentlyContinue | Select-Object -ExpandProperty OwningProcess"`;
      const psOut = execSync(psCmd, { encoding: 'utf-8' });
      for (const pid of psOut.split(/\r?\n/)) {
        const trimmed = pid.trim();
        if (trimmed && trimmed !== '0' && trimmed !== String(process.pid)) {
          pidsToKill.add(trimmed);
        }
      }
    } catch (_) {}

    // Terminate all matching PIDs
    for (const pid of pidsToKill) {
      try {
        execSync(`taskkill /F /T /PID ${pid}`, { stdio: 'ignore' });
        console.log(`[Port Cleaner] Freed port ${targetPort} by terminating PID ${pid}`);
      } catch (_) {}
    }
  } else {
    // macOS / Linux
    try {
      const pids = execSync(`lsof -ti tcp:${targetPort}`, { encoding: 'utf-8' }).trim().split('\n');
      for (const pid of pids) {
        if (pid && pid !== String(process.pid)) {
          execSync(`kill -9 ${pid}`, { stdio: 'ignore' });
          console.log(`[Port Cleaner] Freed port ${targetPort} by terminating PID ${pid}`);
        }
      }
    } catch (_) {}
  }
}

/**
 * Kill a spawned child process and all of its spawned descendant processes.
 */
function killProcessTree(child) {
  if (!child || !child.pid) return;
  try {
    if (process.platform === 'win32') {
      execSync(`taskkill /F /T /PID ${child.pid}`, { stdio: 'ignore' });
    } else {
      process.kill(-child.pid, 'SIGKILL');
    }
  } catch (_) {
    try {
      child.kill('SIGKILL');
    } catch (__) {}
  }
}

module.exports = {
  freePort,
  killProcessTree,
};
