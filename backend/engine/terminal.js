const { spawn } = require('child_process');
const pty = require('node-pty');

function defaultShell() {
  if (process.platform === 'win32') {
    return process.env.ComSpec || process.env.COMSPEC || 'cmd.exe';
  }
  return process.env.SHELL || '/bin/bash';
}

/// A terminal is intentionally separate from one-off agent commands. It keeps
/// its shell state (working directory, environment, interactive programs) for
/// the lifetime of one authenticated WebSocket connection.
function createTerminal({ cwd, cols = 100, rows = 30, shell = defaultShell(), onData, onExit }) {
  const terminal = pty.spawn(shell, [], {
    name: 'xterm-256color',
    cols: Math.max(20, Number(cols) || 100),
    rows: Math.max(5, Number(rows) || 30),
    cwd,
    env: process.env,
  });

  if (onData) terminal.onData(onData);
  if (onExit) terminal.onExit(onExit);
  return terminal;
}

function closeTerminal(terminal) {
  if (!terminal) return;
  try {
    // Ask the shell to stop first. On Windows this avoids abruptly tearing
    // down the ConPTY host (and gives child processes a chance to flush).
    terminal.write('\u0003exit\r');
    const forceCloseTimer = setTimeout(() => {
      try {
        terminal.kill();
      } catch (_) {
        // The shell exited gracefully before the fallback was needed.
      }
    }, 1000);
    forceCloseTimer.unref();
  } catch (error) {
    try {
      terminal.kill();
    } catch (_) {
      console.error('Failed to close terminal:', error.message);
    }
  }
}

function executeCommand(command, cwd, callbacks = {}) {
  // Commands entered in an IDE terminal are intentionally shell commands.
  // On Windows this selects cmd.exe; on POSIX it selects /bin/sh. We keep the
  // shell scoped to this user-command API rather than applying it to process
  // launches that already have an executable and argument array.
  const activeProc = spawn(command, {
    shell: true,
    cwd,
    windowsHide: process.platform === 'win32',
  });

  if (callbacks.onStdout) {
    activeProc.stdout.on('data', (d) => callbacks.onStdout(d.toString()));
  }
  if (callbacks.onStderr) {
    activeProc.stderr.on('data', (d) => callbacks.onStderr(d.toString()));
  }
  if (callbacks.onClose) {
    activeProc.on('close', (code) => callbacks.onClose(code));
  }
  if (callbacks.onError) {
    activeProc.on('error', (err) => callbacks.onError(err));
  }

  return activeProc;
}

function killProcess(activeProc) {
  if (!activeProc) return;
  try {
    if (process.platform === 'win32') {
      // taskkill has a real executable and explicit arguments, so do not
      // invoke a second shell to terminate a process on Windows.
      const killer = spawn('taskkill.exe', ['/F', '/T', '/PID', String(activeProc.pid)], {
        windowsHide: true,
      });
      killer.on('error', (error) => {
        console.error(`Failed to run taskkill: ${error.message}`);
      });
    } else {
      activeProc.kill('SIGINT');
    }
  } catch (e) {
    console.error('Failed to kill process:', e.message);
  }
}

function runCommandPromise(command, cwd, timeoutMs = 60000) {
  return new Promise((resolve, reject) => {
    let stdout = '';
    let stderr = '';

    const proc = spawn(command, {
      shell: true,
      cwd,
      windowsHide: process.platform === 'win32',
    });

    let timer = setTimeout(() => {
      killProcess(proc);
      reject(new Error(`Command timed out after ${timeoutMs / 1000}s: ${command}`));
    }, timeoutMs);

    proc.stdout.on('data', (d) => { stdout += d.toString(); });
    proc.stderr.on('data', (d) => { stderr += d.toString(); });

    proc.on('close', (code) => {
      clearTimeout(timer);
      resolve({
        exitCode: code,
        stdout: stdout.trim(),
        stderr: stderr.trim(),
        success: code === 0,
      });
    });

    proc.on('error', (err) => {
      clearTimeout(timer);
      reject(err);
    });
  });
}

module.exports = {
  createTerminal,
  closeTerminal,
  defaultShell,
  executeCommand,
  killProcess,
  runCommandPromise,
};
