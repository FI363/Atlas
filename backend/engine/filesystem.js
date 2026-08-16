const fs = require('fs');
const path = require('path');
const os = require('os');
const { execFile } = require('child_process');

function resolveWorkspacePath(workspaceRoot, relativePath) {
  if (typeof relativePath !== 'string' || relativePath.length === 0) return null;
  const resolved = path.resolve(workspaceRoot, relativePath);
  const relative = path.relative(workspaceRoot, resolved);
  return relative && !relative.startsWith(`..${path.sep}`) && relative !== '..' && !path.isAbsolute(relative)
    ? resolved
    : (resolved === workspaceRoot ? workspaceRoot : null);
}

function buildTree(dirPath, depth = 0, maxDepth = 3) {
  const entries = [];
  try {
    for (const item of fs.readdirSync(dirPath, { withFileTypes: true })) {
      if (item.name.startsWith('.') || item.name === 'build' || item.name === 'node_modules') continue;

      if (item.isDirectory()) {
        entries.push({
          name: item.name,
          type: 'dir',
          children: depth < maxDepth ? buildTree(path.join(dirPath, item.name), depth + 1, maxDepth) : [],
        });
      } else {
        entries.push({ name: item.name, type: 'file' });
      }
    }
  } catch (e) {
    console.error(`Error reading ${dirPath}: ${e.message}`);
  }
  entries.sort((a, b) => {
    if (a.type !== b.type) return a.type === 'dir' ? -1 : 1;
    return a.name.localeCompare(b.name);
  });
  return entries;
}

function createWorkspaceEntry(workspaceRoot, relativePath, isDirectory) {
  const filePath = resolveWorkspacePath(workspaceRoot, relativePath);
  if (!filePath) throw new Error('Path must be inside the project');
  if (fs.existsSync(filePath)) throw new Error('Already exists at that path');
  if (!fs.existsSync(path.dirname(filePath))) throw new Error('Parent folder does not exist');

  if (isDirectory) {
    fs.mkdirSync(filePath, { recursive: true });
  } else {
    fs.writeFileSync(filePath, '', 'utf-8');
  }
}

function readFile(workspaceRoot, relativePath) {
  const filePath = resolveWorkspacePath(workspaceRoot, relativePath);
  if (!filePath) throw new Error('Access denied: Path outside workspace');
  if (!fs.existsSync(filePath)) throw new Error(`File not found: ${relativePath}`);
  if (fs.statSync(filePath).isDirectory()) throw new Error(`Path is a directory: ${relativePath}`);
  return fs.readFileSync(filePath, 'utf-8');
}

function writeFile(workspaceRoot, relativePath, content) {
  const filePath = resolveWorkspacePath(workspaceRoot, relativePath);
  if (!filePath) throw new Error('Access denied: Path outside workspace');
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, content, 'utf-8');
}

function deleteEntry(workspaceRoot, relativePath) {
  const filePath = resolveWorkspacePath(workspaceRoot, relativePath);
  if (!filePath || filePath === workspaceRoot) throw new Error('Invalid path or cannot delete workspace root');
  if (!fs.existsSync(filePath)) throw new Error(`Path not found: ${relativePath}`);
  const stat = fs.statSync(filePath);
  if (stat.isDirectory()) {
    fs.rmSync(filePath, { recursive: true, force: true });
  } else {
    fs.unlinkSync(filePath);
  }
}

function moveEntry(workspaceRoot, sourceRelPath, destRelPath) {
  const srcPath = resolveWorkspacePath(workspaceRoot, sourceRelPath);
  const destPath = resolveWorkspacePath(workspaceRoot, destRelPath);
  if (!srcPath || !destPath) throw new Error('Paths must be inside the workspace');
  if (!fs.existsSync(srcPath)) throw new Error(`Source does not exist: ${sourceRelPath}`);
  fs.mkdirSync(path.dirname(destPath), { recursive: true });
  fs.renameSync(srcPath, destPath);
}

function listDirectory(workspaceRoot, relativePath = '.') {
  const targetDir = relativePath === '.' || relativePath === '' 
    ? workspaceRoot 
    : resolveWorkspacePath(workspaceRoot, relativePath);
  if (!targetDir || !fs.existsSync(targetDir)) throw new Error(`Directory not found: ${relativePath}`);
  if (!fs.statSync(targetDir).isDirectory()) throw new Error(`Not a directory: ${relativePath}`);

  const items = fs.readdirSync(targetDir, { withFileTypes: true });
  return items.map(item => ({
    name: item.name,
    isDirectory: item.isDirectory(),
    isFile: item.isFile(),
    path: path.relative(workspaceRoot, path.join(targetDir, item.name)).replace(/\\/g, '/')
  }));
}

function mimeFromPath(filePath) {
  const ext = path.extname(filePath).toLowerCase();
  if (ext === '.png') return 'image/png';
  if (ext === '.jpg' || ext === '.jpeg') return 'image/jpeg';
  if (ext === '.gif') return 'image/gif';
  if (ext === '.webp') return 'image/webp';
  if (ext === '.bmp') return 'image/bmp';
  if (ext === '.svg') return 'image/svg+xml';
  if (['.txt', '.md', '.json', '.dart', '.js', '.ts', '.html', '.css', '.yaml', '.yml', '.xml', '.csv', '.sh', '.ps1'].includes(ext)) return 'text/plain';
  return 'application/octet-stream';
}

function readAttachmentFromPath(filePath, workspaceRoot) {
  const resolved = path.isAbsolute(filePath) ? filePath : resolveWorkspacePath(workspaceRoot, filePath);
  if (!resolved || !fs.existsSync(resolved) || !fs.statSync(resolved).isFile()) return null;
  const mimeType = mimeFromPath(resolved);
  const stat = fs.statSync(resolved);
  if (mimeType.startsWith('image/')) {
    return {
      kind: 'image',
      name: path.basename(resolved),
      path: resolved,
      mimeType,
      size: stat.size,
      dataBase64: fs.readFileSync(resolved).toString('base64'),
    };
  }
  if (mimeType === 'text/plain' || stat.size <= 200000) {
    return {
      kind: 'file',
      name: path.basename(resolved),
      path: resolved,
      mimeType,
      size: stat.size,
      text: fs.readFileSync(resolved, 'utf-8'),
    };
  }
  return {
    kind: 'file',
    name: path.basename(resolved),
    path: resolved,
    mimeType,
    size: stat.size,
  };
}

function readClipboardAttachment(callback) {
  if (process.platform !== 'win32') {
    return callback(new Error('Clipboard image paste is currently supported on Windows only.'));
  }

  const tempDir = os.tmpdir();
  const outputPath = path.join(tempDir, `atlas-clipboard-${Date.now()}.png`);
  const script = `
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    if ([Windows.Forms.Clipboard]::ContainsImage()) {
      $img = [Windows.Forms.Clipboard]::GetImage()
      $img.Save('${outputPath.replace(/'/g, "''")}')
      [Console]::Write('{"kind":"attachment","attachment":{"name":"clipboard.png","path":"${outputPath.replace(/\\/g, '\\\\')}","mimeType":"image/png","type":"image"}}')
    } elseif ([Windows.Forms.Clipboard]::ContainsText()) {
      $text = [Windows.Forms.Clipboard]::GetText()
      $json = @{ kind = 'text'; text = $text } | ConvertTo-Json -Compress
      [Console]::Write($json)
    }
  `;
  execFile('powershell.exe', ['-NoProfile', '-STA', '-Command', script], (err, stdout) => {
    if (err) return callback(err);
    const output = (stdout || '').trim();
    if (!output) return callback(new Error('Clipboard is empty.'));
    try {
      const result = JSON.parse(output);
      if (result && result.attachment && result.attachment.path) {
        const attachment = readAttachmentFromPath(result.attachment.path, process.cwd());
        if (attachment) result.attachment = attachment;
      }
      callback(null, result);
    } catch (parseErr) {
      callback(parseErr);
    }
  });
}

module.exports = {
  resolveWorkspacePath,
  buildTree,
  createWorkspaceEntry,
  readFile,
  writeFile,
  deleteEntry,
  moveEntry,
  listDirectory,
  mimeFromPath,
  readAttachmentFromPath,
  readClipboardAttachment,
};
