const { spawn, exec } = require('child_process');

function executeCommand(command, cwd, callbacks = {}) {
  const activeProc = spawn(command, { shell: true, cwd });

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
      spawn(`taskkill /F /T /PID ${activeProc.pid}`, { shell: true });
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

    const proc = spawn(command, { shell: true, cwd });

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
  executeCommand,
  killProcess,
  runCommandPromise,
};
