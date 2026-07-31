const WebSocket = require('ws');
const { spawn } = require('child_process');
const fs = require('fs');
const path = require('path');
const os = require('os');

const PORT = 8080;
const PROJECT_ROOT = path.resolve(__dirname, '..'); // atlas/ directory
const wss = new WebSocket.Server({ port: PORT, host: '0.0.0.0' });

console.log(`Atlas Remote Engine starting on ws://0.0.0.0:${PORT}`);
console.log(`Project root: ${PROJECT_ROOT}`);

function sendJson(ws, payload) {
  ws.send(JSON.stringify(payload));
}

function resolveProjectFilePath(requestedPath) {
  const resolvedPath = path.resolve(PROJECT_ROOT, requestedPath);
  const relativePath = path.relative(PROJECT_ROOT, resolvedPath);
  const isSafe = relativePath && !relativePath.startsWith('..') && !path.isAbsolute(relativePath);

  if (!isSafe) {
    return null;
  }

  return resolvedPath;
}

// Recursively build a file tree (max 2 levels deep to avoid huge payloads)
function buildTree(dirPath, depth = 0, maxDepth = 3) {
  const entries = [];
  try {
    const items = fs.readdirSync(dirPath, { withFileTypes: true });
    for (const item of items) {
      // Skip hidden dirs, build, node_modules
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
    console.error(`Error reading dir ${dirPath}:`, e.message);
  }
  // Sort: directories first, then files, alphabetical within each group
  entries.sort((a, b) => {
    if (a.type !== b.type) return a.type === 'dir' ? -1 : 1;
    return a.name.localeCompare(b.name);
  });
  return entries;
}

wss.on('connection', (ws) => {
  console.log('Client connected from iPad!');

  sendJson(ws, {
    type: 'system',
    message: `Connected to Atlas Remote Engine (${os.type()} ${os.release()})`
  });

  ws.on('message', (message) => {
    try {
      const data = JSON.parse(message);
      
      if (data.type === 'cmd') {
        const command = data.command;
        console.log(`Executing: ${command}`);

        const proc = spawn(command, { shell: true, cwd: PROJECT_ROOT });

        proc.stdout.on('data', (outData) => {
          sendJson(ws, { type: 'output', content: outData.toString() });
        });

        proc.stderr.on('data', (errData) => {
          sendJson(ws, { type: 'error', content: errData.toString() });
        });

        proc.on('close', (code) => {
          sendJson(ws, { type: 'exit', code });
        });

        proc.on('error', (err) => {
          sendJson(ws, { type: 'error', content: err.toString() });
        });

      } else if (data.type === 'list_dir') {
        console.log('Sending file tree...');
        const tree = buildTree(PROJECT_ROOT);
        sendJson(ws, { type: 'file_tree', children: tree });

      } else if (data.type === 'read_file') {
        const filePath = resolveProjectFilePath(data.path);
        console.log(`Reading file: ${filePath || data.path}`);

        if (!filePath) {
          sendJson(ws, { type: 'file_content', path: data.path, content: '[ACCESS DENIED]' });
          return;
        }

        try {
          const content = fs.readFileSync(filePath, 'utf-8');
          sendJson(ws, { type: 'file_content', path: data.path, content });
        } catch (e) {
          sendJson(ws, { type: 'file_content', path: data.path, content: `[Error reading file: ${e.message}]` });
        }
      } else if (data.type === 'write_file') {
        const filePath = resolveProjectFilePath(data.path);
        console.log(`Writing file: ${filePath || data.path}`);

        if (!filePath) {
          sendJson(ws, { type: 'error', content: 'Access denied: invalid file path.' });
          return;
        }

        try {
          fs.writeFileSync(filePath, data.content ?? '', 'utf-8');
          sendJson(ws, { type: 'file_content', path: data.path, content: data.content ?? '' });
        } catch (e) {
          sendJson(ws, { type: 'error', content: `Error writing file: ${e.message}` });
        }
      }
    } catch (err) {
      console.error('Error handling message:', err);
    }
  });

  ws.on('close', () => {
    console.log('Client disconnected.');
  });
});

