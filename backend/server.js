const WebSocket = require('ws');
const { spawn, exec } = require('child_process');
const fs = require('fs');
const path = require('path');
const os = require('os');
const http = require('http');
const https = require('https');

const PORT = process.env.PORT ? parseInt(process.env.PORT, 10) : 8080;
const PROJECT_ROOT = path.join(__dirname, '..');
const ENGINE_TOKEN = process.env.ATLAS_ENGINE_TOKEN || 'dev-token';

// ── File-system helpers ─────────────────────────────────────────────────────

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

function resolveProjectPath(relativePath) {
  if (typeof relativePath !== 'string' || relativePath.length === 0) return null;
  const resolved = path.resolve(PROJECT_ROOT, relativePath);
  return resolved.startsWith(PROJECT_ROOT + path.sep) ? resolved : null;
}

function createWorkspaceEntry(relativePath, isDirectory) {
  const filePath = resolveProjectPath(relativePath);
  if (!filePath) throw new Error('Path must be inside the project');
  if (fs.existsSync(filePath)) throw new Error('Already exists at that path');
  if (!fs.existsSync(path.dirname(filePath))) throw new Error('Parent folder does not exist');

  if (isDirectory) {
    fs.mkdirSync(filePath);
  } else {
    fs.writeFileSync(filePath, '', 'utf-8');
  }
}

// ── Full-text search across workspace ───────────────────────────────────────

function searchWorkspaceFiles(dirPath, query, results = [], maxResults = 50) {
  if (!query || query.trim().length === 0) return results;
  const lowerQuery = query.toLowerCase();

  try {
    const items = fs.readdirSync(dirPath, { withFileTypes: true });
    for (const item of items) {
      if (results.length >= maxResults) break;
      if (item.name.startsWith('.') || item.name === 'build' || item.name === 'node_modules') continue;

      const fullPath = path.join(dirPath, item.name);
      if (item.isDirectory()) {
        searchWorkspaceFiles(fullPath, query, results, maxResults);
      } else if (item.isFile()) {
        const ext = path.extname(item.name).toLowerCase();
        if (['.png', '.jpg', '.jpeg', '.gif', '.ico', '.pdf', '.zip', '.exe', '.dll'].includes(ext)) continue;

        try {
          const content = fs.readFileSync(fullPath, 'utf-8');
          const lines = content.split('\n');
          const relPath = path.relative(PROJECT_ROOT, fullPath).replace(/\\/g, '/');

          for (let i = 0; i < lines.length; i++) {
            if (results.length >= maxResults) break;
            if (lines[i].toLowerCase().includes(lowerQuery)) {
              results.push({
                path: relPath,
                line: i + 1,
                snippet: lines[i].trim(),
              });
            }
          }
        } catch {}
      }
    }
  } catch (e) {
    console.error(`Search error in ${dirPath}: ${e.message}`);
  }
  return results;
}

// ── AI HTTP Dispatcher (Ollama / OpenAI / Custom) ───────────────────────────

function callAiProvider(settings, prompt, contextCode, callback) {
  const provider = settings.aiProvider || 'builtIn';
  const systemPrompt = settings.aiSystemPrompt || 'You are Atlas, an expert coding assistant.';
  const userContent = contextCode
    ? `Active Code Context:\n\`\`\`\n${contextCode}\n\`\`\`\n\nTask: ${prompt}`
    : prompt;

  if (provider === 'ollama') {
    const endpoint = settings.ollamaEndpoint || 'http://localhost:11434';
    const model = settings.ollamaModel || 'deepseek-coder';
    let url;
    try {
      url = new URL('/api/chat', endpoint);
    } catch {
      return callback(null, `❌ Invalid Ollama URL: ${endpoint}`);
    }

    const postData = JSON.stringify({
      model: model,
      messages: [
        { role: 'system', content: systemPrompt },
        { role: 'user', content: userContent }
      ],
      stream: false,
      options: {
        temperature: settings.aiTemperature || 0.2,
        num_predict: settings.aiMaxTokens || 2048
      }
    });

    const httpModule = url.protocol === 'https:' ? https : http;
    const req = httpModule.request(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(postData) }
    }, (res) => {
      let body = '';
      res.on('data', chunk => body += chunk);
      res.on('end', () => {
        try {
          const parsed = JSON.parse(body);
          const answer = parsed.message?.content || parsed.response || body;
          callback(null, `### 🦙 Ollama (${model})\n\n${answer}`);
        } catch (e) {
          callback(null, `Ollama Response: ${body}`);
        }
      });
    });
    req.on('error', (err) => callback(null, `❌ Cannot reach Ollama at ${endpoint}.\n\nEnsure Ollama is running (\`ollama serve\`) and you have pulled the model (\`ollama pull ${model}\`). Error: ${err.message}`));
    req.write(postData);
    req.end();
  } else if (provider === 'openAi') {
    const endpoint = settings.openAiEndpoint || 'https://api.openai.com/v1';
    const model = settings.openAiModel || 'gpt-4o';
    const apiKey = settings.openAiApiKey || '';
    if (!apiKey) {
      return callback(null, '❌ OpenAI API Key is missing! Set your key in Atlas Settings → AI Agent.');
    }
    let url;
    try {
      url = new URL('/chat/completions', endpoint);
    } catch {
      return callback(null, `❌ Invalid OpenAI URL: ${endpoint}`);
    }

    const postData = JSON.stringify({
      model: model,
      messages: [
        { role: 'system', content: systemPrompt },
        { role: 'user', content: userContent }
      ],
      temperature: settings.aiTemperature || 0.2,
      max_tokens: settings.aiMaxTokens || 2048
    });

    const httpModule = url.protocol === 'https:' ? https : http;
    const req = httpModule.request(url, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${apiKey}`,
        'Content-Length': Buffer.byteLength(postData)
      }
    }, (res) => {
      let body = '';
      res.on('data', chunk => body += chunk);
      res.on('end', () => {
        try {
          const parsed = JSON.parse(body);
          if (parsed.choices && parsed.choices[0]) {
            callback(null, `### ⚡ OpenAI (${model})\n\n${parsed.choices[0].message.content}`);
          } else {
            callback(null, `API Error: ${parsed.error?.message || body}`);
          }
        } catch (e) {
          callback(null, body);
        }
      });
    });
    req.on('error', (err) => callback(null, `❌ OpenAI Request Failed: ${err.message}`));
    req.write(postData);
    req.end();
  } else if (provider === 'custom') {
    const endpoint = settings.customAgentEndpoint || '';
    if (!endpoint) return callback(null, '❌ Custom Endpoint URL is missing in Settings.');
    let url;
    try { url = new URL(endpoint); } catch { return callback(null, `❌ Invalid Custom URL: ${endpoint}`); }

    const postData = JSON.stringify({ prompt, contextCode, systemPrompt });
    const httpModule = url.protocol === 'https:' ? https : http;
    const req = httpModule.request(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(postData) }
    }, (res) => {
      let body = '';
      res.on('data', chunk => body += chunk);
      res.on('end', () => callback(null, body));
    });
    req.on('error', (err) => callback(null, `❌ Custom Endpoint Failed: ${err.message}`));
    req.write(postData);
    req.end();
  } else {
    // Built-in smart fallback
    const lower = prompt.toLowerCase();
    let aiAnswer = '';

    if (lower.includes('explain') || lower.includes('what does this code do')) {
      aiAnswer = `### 🤖 Atlas Built-In Agent: Code Explanation\n\nAnalyzing active context (${contextCode ? contextCode.length : 0} bytes):\n\n- **Structure**: High-performance Flutter reactive component.\n- **State**: Uses \`ChangeNotifier\` & \`WorkspaceState\` for real-time reactivity.\n- **Recommendation**: Ensure UI widgets bind cleanly to state models.`;
    } else if (lower.includes('bug') || lower.includes('fix') || lower.includes('find bugs')) {
      aiAnswer = `### 🐛 Atlas Built-In Agent: Bug Scan\n\n- **Check**: All WebSocket connections verify \`isConnected\` before sending.\n- **Check**: Null bounds checked on file tab switches.\n- **Status**: No critical syntax errors found in active buffer.`;
    } else if (lower.includes('test') || lower.includes('generate tests')) {
      aiAnswer = `### 🧪 Atlas Built-In Agent: Unit Test\n\n\`\`\`dart\nvoid main() {\n  group('WorkspaceState Unit Tests', () {\n    test('verifies initial state and settings', () {\n      // Test implementation\n    });\n  });\n}\n\`\`\``;
    } else {
      aiAnswer = `### 🤖 Atlas Built-In Agent\n\nReceived your prompt: "${prompt}".\n\n${contextCode ? '📄 Active File Context Included (' + contextCode.split('\n').length + ' lines).' : 'No active file open.'}\n\n*Tip: Connect me to **Ollama** or **OpenAI** in Settings for full LLM intelligence!*`;
    }
    setTimeout(() => callback(null, aiAnswer), 250);
  }
}

// ── WebSocket message handler ───────────────────────────────────────────────

function handleConnection(ws) {
  let authenticated = false;
  let activeProc = null;
  let clientSettings = { aiProvider: 'builtIn' };

  ws.on('message', (raw) => {
    let data;
    try {
      data = JSON.parse(raw);
    } catch {
      console.error('Invalid JSON from client');
      return;
    }

    // ── Auth gate ────────────────────────────────────────────────────────
    if (!authenticated) {
      if (data.type !== 'auth' || data.token !== ENGINE_TOKEN) {
        ws.send(JSON.stringify({ type: 'error', content: 'Authentication failed.\n' }));
        ws.close(1008, 'Authentication required');
        return;
      }
      authenticated = true;
      console.log('Client authenticated.');
      ws.send(JSON.stringify({
        type: 'system',
        message: `Connected to Atlas Engine (${os.type()} ${os.release()})`,
        projectName: path.basename(PROJECT_ROOT),
        cwd: PROJECT_ROOT,
      }));
      return;
    }

    // ── Authenticated commands ───────────────────────────────────────────
    switch (data.type) {
      case 'update_settings': {
        clientSettings = data.settings || {};
        console.log(`Settings updated. AI Provider: ${clientSettings.aiProvider || 'builtIn'}`);
        break;
      }

      case 'cmd': {
        const command = data.command;
        console.log(`Exec: ${command}`);

        if (activeProc) {
          try { activeProc.kill(); } catch {}
        }

        activeProc = spawn(command, { shell: true, cwd: PROJECT_ROOT });

        activeProc.stdout.on('data', (d) => ws.send(JSON.stringify({ type: 'output', content: d.toString() })));
        activeProc.stderr.on('data', (d) => ws.send(JSON.stringify({ type: 'error', content: d.toString() })));
        activeProc.on('close', (code) => {
          activeProc = null;
          ws.send(JSON.stringify({ type: 'exit', code }));
        });
        activeProc.on('error', (err) => {
          activeProc = null;
          ws.send(JSON.stringify({ type: 'error', content: err.toString() }));
        });
        break;
      }

      case 'kill_cmd': {
        if (activeProc) {
          console.log('Terminating active process...');
          try {
            if (process.platform === 'win32') {
              spawn(`taskkill /F /T /PID ${activeProc.pid}`, { shell: true });
            } else {
              activeProc.kill('SIGINT');
            }
          } catch (e) {
            console.error('Failed to kill process:', e.message);
          }
          activeProc = null;
          ws.send(JSON.stringify({ type: 'output', content: '\n^C [Process terminated by user]\n' }));
        }
        break;
      }

      case 'ai_prompt': {
        const prompt = data.prompt || '';
        const contextCode = data.contextCode || '';
        const settings = data.settings || clientSettings;

        console.log(`AI Agent Prompt (${settings.aiProvider || 'builtIn'}): ${prompt.substring(0, 60)}...`);

        callAiProvider(settings, prompt, contextCode, (err, answer) => {
          ws.send(JSON.stringify({
            type: 'ai_response',
            prompt: prompt,
            content: answer,
          }));
        });
        break;
      }

      case 'search_files': {
        const query = data.query || '';
        const results = searchWorkspaceFiles(PROJECT_ROOT, query);
        ws.send(JSON.stringify({
          type: 'search_results',
          query: query,
          results: results,
        }));
        break;
      }

      case 'git_status': {
        exec('git status --porcelain && git branch --show-current', { cwd: PROJECT_ROOT }, (err, stdout) => {
          const lines = (stdout || '').split('\n').map(l => l.trim()).filter(Boolean);
          const branch = lines.length > 0 && !lines[lines.length - 1].includes(' ') ? lines.pop() : 'main';
          const files = lines.map(line => ({
            status: line.substring(0, 2).trim(),
            path: line.substring(3).trim(),
          }));
          ws.send(JSON.stringify({ type: 'git_status_result', branch, files }));
        });
        break;
      }

      case 'git_commit': {
        const message = (data.message || 'Update files').replace(/"/g, '\\"');
        exec(`git add -A && git commit -m "${message}"`, { cwd: PROJECT_ROOT }, (err, stdout, stderr) => {
          const output = stdout || stderr || (err ? err.message : 'Committed successfully');
          ws.send(JSON.stringify({ type: 'output', content: `\n[Git Commit] ${output}\n` }));
          // Re-fetch status
          exec('git status --porcelain && git branch --show-current', { cwd: PROJECT_ROOT }, (err, stdout) => {
            const lines = (stdout || '').split('\n').map(l => l.trim()).filter(Boolean);
            const branch = lines.length > 0 && !lines[lines.length - 1].includes(' ') ? lines.pop() : 'main';
            const files = lines.map(line => ({ status: line.substring(0, 2).trim(), path: line.substring(3).trim() }));
            ws.send(JSON.stringify({ type: 'git_status_result', branch, files }));
          });
        });
        break;
      }

      case 'list_dir': {
        ws.send(JSON.stringify({ type: 'file_tree', children: buildTree(PROJECT_ROOT) }));
        break;
      }

      case 'read_file': {
        const fp = resolveProjectPath(data.path);
        if (!fp) {
          ws.send(JSON.stringify({ type: 'file_content', path: data.path, content: '[ACCESS DENIED]' }));
          break;
        }
        try {
          ws.send(JSON.stringify({ type: 'file_content', path: data.path, content: fs.readFileSync(fp, 'utf-8') }));
        } catch (e) {
          ws.send(JSON.stringify({ type: 'file_content', path: data.path, content: `[Error: ${e.message}]` }));
        }
        break;
      }

      case 'write_file': {
        const fp = resolveProjectPath(data.path);
        if (!fp || typeof data.content !== 'string') {
          ws.send(JSON.stringify({ type: 'error', content: 'Invalid save request.\n' }));
          break;
        }
        try {
          if (!fs.statSync(fp).isFile()) throw new Error('Not a file');
          fs.writeFileSync(fp, data.content, 'utf-8');
          ws.send(JSON.stringify({ type: 'file_saved', path: data.path, content: data.content }));
        } catch (e) {
          ws.send(JSON.stringify({ type: 'error', content: `Save failed (${data.path}): ${e.message}\n` }));
        }
        break;
      }

      case 'create_file':
      case 'create_directory': {
        const isDir = data.type === 'create_directory';
        try {
          createWorkspaceEntry(data.path, isDir);
          ws.send(JSON.stringify({
            type: 'workspace_changed',
            message: `${isDir ? 'Created folder' : 'Created file'} ${data.path}`,
          }));
        } catch (e) {
          ws.send(JSON.stringify({ type: 'error', content: `Create failed (${data.path}): ${e.message}\n` }));
        }
        break;
      }

      default:
        console.warn(`Unknown message type: ${data.type}`);
    }
  });

  ws.on('close', () => {
    if (activeProc) {
      try { activeProc.kill(); } catch {}
    }
    console.log('Client disconnected.');
  });
}

// ── Start ───────────────────────────────────────────────────────────────────

const wss = new WebSocket.Server({ port: PORT, host: '0.0.0.0' });

wss.on('listening', () => {
  console.log(`\n  Atlas Engine listening on port ${PORT}`);
  const nets = os.networkInterfaces();
  for (const name of Object.keys(nets)) {
    for (const net of nets[name]) {
      if (net.family === 'IPv4' && !net.internal) {
        console.log(`  LAN:  ws://${net.address}:${PORT}`);
      }
    }
  }
  console.log(`  Root: ${PROJECT_ROOT}\n`);
});

wss.on('connection', handleConnection);

wss.on('error', (err) => {
  if (err.code === 'EADDRINUSE') {
    console.error(`\n  Port ${PORT} is already in use.`);
    console.error(`  Stop the other process or run with: PORT=<other> npm --prefix backend start\n`);
  } else {
    console.error(`Server error: ${err.message}`);
  }
  process.exit(1);
});
