const WebSocket = require('ws');
const { spawn } = require('child_process');
const fs = require('fs');
const path = require('path');
const os = require('os');

const DEFAULT_PORT = process.env.PORT ? parseInt(process.env.PORT, 10) : 8080;
const PROJECT_ROOT = path.join(__dirname, '..'); // atlas/ directory
const ENGINE_TOKEN = process.env.ATLAS_ENGINE_TOKEN || 'dev-token';

if (!ENGINE_TOKEN) {
  console.error('ATLAS_ENGINE_TOKEN is required. Refusing to start an unauthenticated engine.');
  process.exit(1);
}

// Create the WebSocket server with retry logic when the requested port is in use.
let wss;
function startServer(port, maxAttempts = 20) {
  let attempts = 0;

  function tryPort(p) {
    attempts++;
    const server = new WebSocket.Server({ port: p, host: '0.0.0.0' });

    server.on('listening', () => {
      console.log(`Atlas Remote Engine starting on port ${p}`);
      const networkInterfaces = os.networkInterfaces();
      for (const name of Object.keys(networkInterfaces)) {
        for (const net of networkInterfaces[name]) {
          if (net.family === 'IPv4' && !net.internal) {
            console.log(`  Accessible on LAN at: ws://${net.address}:${p}`);
          }
        }
      }
      console.log(`Project root: ${PROJECT_ROOT}`);
    });

    server.on('error', (err) => {
      if (err && err.code === 'EADDRINUSE' && attempts < maxAttempts) {
        console.warn(`Port ${p} in use, trying port ${p + 1}...`);
        // Small delay before retrying to avoid a tight loop
        setTimeout(() => tryPort(p + 1), 200);
        return;
      }

      // If it's not an address-in-use error or we've exhausted attempts, log and exit
      console.error(`Failed to start WebSocket server on port ${p}:`, err && err.message ? err.message : err);
      process.exit(1);
    });

    // Assign the server so the rest of the file can attach handlers to `wss`.
    wss = server;
    return server;
  }

  return tryPort(port);
}

startServer(DEFAULT_PORT);

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

// Resolve a client path while keeping every read and write inside the project.
function resolveProjectPath(relativePath) {
  if (typeof relativePath !== 'string' || relativePath.length === 0) return null;
  const resolvedPath = path.resolve(PROJECT_ROOT, relativePath);
  const projectPrefix = `${PROJECT_ROOT}${path.sep}`;
  return resolvedPath.startsWith(projectPrefix) ? resolvedPath : null;
}

function createWorkspaceEntry(relativePath, isDirectory) {
  const filePath = resolveProjectPath(relativePath);
  if (!filePath) throw new Error('Path must be inside the project');
  if (fs.existsSync(filePath)) throw new Error('A file or folder already exists at that path');
  if (!fs.existsSync(path.dirname(filePath))) throw new Error('Parent folder does not exist');

  if (isDirectory) {
    fs.mkdirSync(filePath);
  } else {
    fs.writeFileSync(filePath, '', 'utf-8');
  }
}

wss.on('connection', (ws) => {
  let isAuthenticated = false;

  ws.on('message', (message) => {
    try {
      const data = JSON.parse(message);

      if (!isAuthenticated) {
        if (data.type !== 'auth' || data.token !== ENGINE_TOKEN) {
          ws.send(JSON.stringify({type: 'error', content: 'Authentication failed.\n'}));
          ws.close(1008, 'Authentication required');
          return;
        }

        isAuthenticated = true;
        console.log('Authenticated Atlas client connected.');
        ws.send(JSON.stringify({
          type: 'system',
          message: `Connected to Atlas Remote Engine (${os.type()} ${os.release()})`,
        }));
        return;
      }
      
      if (data.type === 'cmd') {
        const command = data.command;
        console.log(`Executing: ${command}`);
        
        const parts = command.split(' ');
        const cmd = parts[0];
        const args = parts.slice(1);

        const proc = spawn(cmd, args, { shell: true, cwd: PROJECT_ROOT });

        proc.stdout.on('data', (outData) => {
          ws.send(JSON.stringify({ type: 'output', content: outData.toString() }));
        });

        proc.stderr.on('data', (errData) => {
          ws.send(JSON.stringify({ type: 'error', content: errData.toString() }));
        });

        proc.on('close', (code) => {
          ws.send(JSON.stringify({ type: 'exit', code: code }));
        });
        
        proc.on('error', (err) => {
          ws.send(JSON.stringify({ type: 'error', content: err.toString() }));
        });

      } else if (data.type === 'list_dir') {
        // Return the project file tree
        console.log('Sending file tree...');
        const tree = buildTree(PROJECT_ROOT);
        ws.send(JSON.stringify({ type: 'file_tree', children: tree }));

      } else if (data.type === 'read_file') {
        // Read a file's contents and send back
        const filePath = resolveProjectPath(data.path);
        console.log(`Reading file: ${filePath}`);
        
        if (!filePath) {
          ws.send(JSON.stringify({ type: 'file_content', path: data.path, content: '[ACCESS DENIED]' }));
          return;
        }
        
        try {
          const content = fs.readFileSync(filePath, 'utf-8');
          ws.send(JSON.stringify({ type: 'file_content', path: data.path, content: content }));
        } catch (e) {
          ws.send(JSON.stringify({ type: 'file_content', path: data.path, content: `[Error reading file: ${e.message}]` }));
        }
      } else if (data.type === 'write_file') {
        const filePath = resolveProjectPath(data.path);
        if (!filePath || typeof data.content !== 'string') {
          ws.send(JSON.stringify({type: 'error', content: 'Invalid file save request.\n'}));
          return;
        }

        try {
          const stat = fs.statSync(filePath);
          if (!stat.isFile()) throw new Error('Path is not a file');
          fs.writeFileSync(filePath, data.content, 'utf-8');
          ws.send(JSON.stringify({
            type: 'file_saved',
            path: data.path,
            content: data.content,
          }));
        } catch (e) {
          ws.send(JSON.stringify({
            type: 'error',
            content: `Could not save ${data.path}: ${e.message}\n`,
          }));
        }
      } else if (data.type === 'create_file' || data.type === 'create_directory') {
        const isDirectory = data.type === 'create_directory';
        try {
          createWorkspaceEntry(data.path, isDirectory);
          ws.send(JSON.stringify({
            type: 'workspace_changed',
            message: `${isDirectory ? 'Created folder' : 'Created file'} ${data.path}`,
          }));
        } catch (e) {
          ws.send(JSON.stringify({
            type: 'error',
            content: `Could not create ${data.path}: ${e.message}\n`,
          }));
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
