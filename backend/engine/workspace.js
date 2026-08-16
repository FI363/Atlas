const fs = require('fs');
const path = require('path');
const os = require('os');
const { execFile } = require('child_process');

const WORKSPACE_STATE_FILE = path.join(os.homedir(), '.atlas', 'workspace.json');
const DEFAULT_PROJECT_ROOT = path.resolve(__dirname, '..', '..');

function loadPersistedWorkspaceRoot() {
  try {
    const saved = JSON.parse(fs.readFileSync(WORKSPACE_STATE_FILE, 'utf-8'));
    const candidate = typeof saved.path === 'string' ? path.resolve(saved.path) : '';
    if (candidate && fs.existsSync(candidate) && fs.statSync(candidate).isDirectory()) return candidate;
  } catch { }
  return DEFAULT_PROJECT_ROOT;
}

function persistWorkspaceRoot(workspaceRoot) {
  try {
    fs.mkdirSync(path.dirname(WORKSPACE_STATE_FILE), { recursive: true });
    fs.writeFileSync(WORKSPACE_STATE_FILE, JSON.stringify({ path: workspaceRoot }, null, 2), 'utf-8');
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
  loadPersistedWorkspaceRoot,
  persistWorkspaceRoot,
  selectFolder,
  selectFiles,
};
