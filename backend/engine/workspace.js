const fs = require('fs');
const path = require('path');
const os = require('os');
const { execFile } = require('child_process');

const WORKSPACE_STATE_FILE = path.join(os.homedir(), '.atlas', 'workspace.json');
const DEFAULT_PROJECT_ROOT = path.resolve(__dirname, '..', '..');

function isExistingDirectory(candidate) {
  return !!candidate && fs.existsSync(candidate) && fs.statSync(candidate).isDirectory();
}

function loadWorkspaceState() {
  let saved = {};
  try {
    saved = JSON.parse(fs.readFileSync(WORKSPACE_STATE_FILE, 'utf-8'));
  } catch { }

  const legacyPath = typeof saved.path === 'string' ? path.resolve(saved.path) : '';
  const trustedRoots = Array.isArray(saved.trustedRoots)
    ? saved.trustedRoots.filter((entry) => typeof entry === 'string').map((entry) => path.resolve(entry))
    : [];

  // Existing single-workspace settings are migrated without locking a current
  // user out of their own established Atlas workspace.
  if (legacyPath && isExistingDirectory(legacyPath) && !trustedRoots.includes(legacyPath)) {
    trustedRoots.push(legacyPath);
  }
  if (!trustedRoots.includes(DEFAULT_PROJECT_ROOT)) trustedRoots.push(DEFAULT_PROJECT_ROOT);

  const recentRoots = Array.isArray(saved.recentRoots)
    ? saved.recentRoots.filter((entry) => typeof entry === 'string').map((entry) => path.resolve(entry))
    : [];
  const currentRoot = isExistingDirectory(legacyPath) && trustedRoots.includes(legacyPath)
    ? legacyPath
    : DEFAULT_PROJECT_ROOT;

  return { currentRoot, trustedRoots, recentRoots };
}

function loadPersistedWorkspaceRoot() {
  return loadWorkspaceState().currentRoot;
}

function isTrustedWorkspace(workspaceRoot) {
  const candidate = path.resolve(workspaceRoot);
  return loadWorkspaceState().trustedRoots.includes(candidate);
}

function persistWorkspaceRoot(workspaceRoot, { trust = false } = {}) {
  try {
    fs.mkdirSync(path.dirname(WORKSPACE_STATE_FILE), { recursive: true });
    const resolvedRoot = path.resolve(workspaceRoot);
    const state = loadWorkspaceState();
    const trustedRoots = [...state.trustedRoots];
    if (trust && !trustedRoots.includes(resolvedRoot)) trustedRoots.push(resolvedRoot);
    const recentRoots = [resolvedRoot, ...state.recentRoots.filter((entry) => entry !== resolvedRoot)]
      .filter(isExistingDirectory)
      .slice(0, 10);
    fs.writeFileSync(WORKSPACE_STATE_FILE, JSON.stringify({
      path: resolvedRoot,
      trustedRoots,
      recentRoots,
    }, null, 2), 'utf-8');
  } catch (error) {
    console.error(`Could not persist workspace path: ${error.message}`);
  }
}

function selectFolder(callback) {
  if (process.platform === 'win32') {
    const script = "Add-Type -AssemblyName System.Windows.Forms; $dialog = New-Object System.Windows.Forms.FolderBrowserDialog; $dialog.Description = 'Open Folder in Atlas'; if ($dialog.ShowDialog() -eq 'OK') { [Console]::Write($dialog.SelectedPath) }";
    execFile('powershell.exe', ['-NoProfile', '-Command', script], (err, stdout) => callback(err, stdout ? stdout.trim() : ''));
  } else if (process.platform === 'darwin') {
    execFile('osascript', ['-e', 'POSIX path of (choose folder with prompt "Open Folder in Atlas")'], (err, stdout) => callback(err, stdout ? stdout.trim() : ''));
  } else {
    execFile('zenity', ['--file-selection', '--directory', '--title=Open Folder in Atlas'], (err, stdout) => callback(err, stdout ? stdout.trim() : ''));
  }
}

function selectFiles(callback) {
  if (process.platform === 'win32') {
    const script = "Add-Type -AssemblyName System.Windows.Forms; $dialog = New-Object System.Windows.Forms.OpenFileDialog; $dialog.Multiselect = $true; $dialog.Filter = 'All files (*.*)|*.*'; $dialog.Title = 'Attach files to Atlas AI'; if ($dialog.ShowDialog() -eq 'OK') { [Console]::Write(($dialog.FileNames -join \"`n\")) }";
    execFile('powershell.exe', ['-NoProfile', '-Command', script], (err, stdout) => callback(err, stdout ? stdout.trim().split('\n').filter(Boolean) : []));
  } else if (process.platform === 'darwin') {
    const script = 'set chosenFiles to choose file with prompt "Attach files to Atlas AI" with multiple selections allowed\nPOSIX path of chosenFiles';
    execFile('osascript', ['-e', script], (err, stdout) => callback(err, stdout ? stdout.trim().split('\n').filter(Boolean) : []));
  } else {
    execFile('zenity', ['--file-selection', '--multiple', '--separator=\n', '--title=Attach files to Atlas AI'], (err, stdout) => callback(err, stdout ? stdout.trim().split('\n').filter(Boolean) : []));
  }
}

module.exports = {
  DEFAULT_PROJECT_ROOT,
  WORKSPACE_STATE_FILE,
  loadWorkspaceState,
  loadPersistedWorkspaceRoot,
  isTrustedWorkspace,
  persistWorkspaceRoot,
  selectFolder,
  selectFiles,
};
