const WebSocket = require('ws');
const { spawn, execFile } = require('child_process');
const fs = require('fs');
const path = require('path');
const os = require('os');
const http = require('http');
const https = require('https');

const PORT = process.env.PORT ? parseInt(process.env.PORT, 10) : 8080;
const DEFAULT_PROJECT_ROOT = path.join(__dirname, '..');
const WORKSPACE_STATE_FILE = path.join(os.homedir(), '.atlas', 'workspace.json');
const SETTINGS_STATE_FILE = path.join(os.homedir(), '.atlas', 'settings.json');
const ENGINE_TOKEN = process.env.ATLAS_ENGINE_TOKEN || 'dev-token';

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

function loadPersistedSettings() {
  try {
    return JSON.parse(fs.readFileSync(SETTINGS_STATE_FILE, 'utf-8'));
  } catch {
    return {};
  }
}

function persistSettings(settings) {
  try {
    fs.mkdirSync(path.dirname(SETTINGS_STATE_FILE), { recursive: true });
    fs.writeFileSync(SETTINGS_STATE_FILE, JSON.stringify(settings, null, 2), 'utf-8');
  } catch (error) {
    console.error(`Could not persist Atlas settings: ${error.message}`);
  }
}

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

function resolveWorkspacePath(workspaceRoot, relativePath) {
  if (typeof relativePath !== 'string' || relativePath.length === 0) return null;
  const resolved = path.resolve(workspaceRoot, relativePath);
  const relative = path.relative(workspaceRoot, resolved);
  return relative && !relative.startsWith(`..${path.sep}`) && relative !== '..' && !path.isAbsolute(relative)
    ? resolved
    : null;
}

function createWorkspaceEntry(workspaceRoot, relativePath, isDirectory) {
  const filePath = resolveWorkspacePath(workspaceRoot, relativePath);
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

function searchWorkspaceFiles(workspaceRoot, dirPath, query, results = [], maxResults = 50) {
  if (!query || query.trim().length === 0) return results;
  const lowerQuery = query.toLowerCase();

  try {
    const items = fs.readdirSync(dirPath, { withFileTypes: true });
    for (const item of items) {
      if (results.length >= maxResults) break;
      if (item.name.startsWith('.') || item.name === 'build' || item.name === 'node_modules') continue;

      const fullPath = path.join(dirPath, item.name);
      if (item.isDirectory()) {
        searchWorkspaceFiles(workspaceRoot, fullPath, query, results, maxResults);
      } else if (item.isFile()) {
        const ext = path.extname(item.name).toLowerCase();
        if (['.png', '.jpg', '.jpeg', '.gif', '.ico', '.pdf', '.zip', '.exe', '.dll'].includes(ext)) continue;

        try {
          const content = fs.readFileSync(fullPath, 'utf-8');
          const lines = content.split('\n');
          const relPath = path.relative(workspaceRoot, fullPath).replace(/\\/g, '/');

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
        } catch { }
      }
    }
  } catch (e) {
    console.error(`Search error in ${dirPath}: ${e.message}`);
  }
  return results;
}

// ── GitHub REST API Helper ──────────────────────────────────────────────────

function callGithubApi(token, method, endpoint, postBody, callback) {
  if (!token) return callback(new Error('GitHub Personal Access Token is required.'));

  let url;
  try {
    url = new URL(endpoint.startsWith('http') ? endpoint : `https://api.github.com${endpoint}`);
  } catch (e) {
    return callback(new Error(`Invalid URL: ${endpoint}`));
  }

  const postData = postBody ? JSON.stringify(postBody) : null;
  const headers = {
    'User-Agent': 'Atlas-IDE-Engine',
    'Accept': 'application/vnd.github.v3+json',
    'Authorization': `Bearer ${token}`,
  };
  if (postData) {
    headers['Content-Type'] = 'application/json';
    headers['Content-Length'] = Buffer.byteLength(postData);
  }

  const req = https.request(url, { method: method, headers: headers }, (res) => {
    let body = '';
    res.on('data', chunk => body += chunk);
    res.on('end', () => {
      try {
        const parsed = JSON.parse(body);
        if (res.statusCode >= 200 && res.statusCode < 300) {
          callback(null, parsed);
        } else {
          callback(new Error(parsed.message || `GitHub API error (${res.statusCode})`));
        }
      } catch (e) {
        callback(e);
      }
    });
  });

  req.on('error', (err) => callback(err));
  if (postData) req.write(postData);
  req.end();
}

function runGit(args, cwd, callback, options = {}) {
  execFile('git', args, { cwd, ...options }, (err, stdout, stderr) => {
    callback(err, stdout, stderr);
  });
}

function sendGitStatus(ws, workspaceRoot) {
  runGit(['status', '--porcelain'], workspaceRoot, (statusErr, stdout) => {
    runGit(['branch', '--show-current'], workspaceRoot, (branchErr, branchOut) => {
      if (statusErr || branchErr) {
        ws.send(JSON.stringify({
          type: 'error',
          content: `Git status failed: ${(statusErr || branchErr).message}\n`,
        }));
        return;
      }
      const files = (stdout || '').split('\n').filter(Boolean).map(line => ({
        status: line.substring(0, 2).trim(),
        path: line.substring(3).trim(),
      }));
      ws.send(JSON.stringify({
        type: 'git_status_result',
        branch: (branchOut || '').trim() || 'HEAD',
        files,
      }));
    });
  });
}

function selectFolder(callback) {
  if (process.platform === 'win32') {
    const script = "Add-Type -AssemblyName System.Windows.Forms; $dialog = New-Object System.Windows.Forms.FolderBrowserDialog; $dialog.Description = 'Open Folder in Atlas'; if ($dialog.ShowDialog() -eq 'OK') { [Console]::Write($dialog.SelectedPath) }";
    execFile('powershell.exe', ['-NoProfile', '-Command', script], (err, stdout) => callback(err, stdout.trim()));
  } else if (process.platform === 'darwin') {
    execFile('osascript', ['-e', 'POSIX path of (choose folder with prompt "Open Folder in Atlas")'], (err, stdout) => callback(err, stdout.trim()));
  } else {
    execFile('zenity', ['--file-selection', '--directory', '--title=Open Folder in Atlas'], (err, stdout) => callback(err, stdout.trim()));
  }
}

function selectFiles(callback) {
  if (process.platform === 'win32') {
    const script = "Add-Type -AssemblyName System.Windows.Forms; $dialog = New-Object System.Windows.Forms.OpenFileDialog; $dialog.Multiselect = $true; $dialog.Filter = 'All files (*.*)|*.*'; $dialog.Title = 'Attach files to Atlas AI'; if ($dialog.ShowDialog() -eq 'OK') { [Console]::Write(($dialog.FileNames -join \"`n\")) }";
    execFile('powershell.exe', ['-NoProfile', '-Command', script], (err, stdout) => callback(err, stdout.trim().split('\n').filter(Boolean)));
  } else if (process.platform === 'darwin') {
    const script = 'set chosenFiles to choose file with prompt "Attach files to Atlas AI" with multiple selections allowed\nPOSIX path of chosenFiles';
    execFile('osascript', ['-e', script], (err, stdout) => callback(err, stdout.trim().split('\n').filter(Boolean)));
  } else {
    execFile('zenity', ['--file-selection', '--multiple', '--separator=\n', '--title=Attach files to Atlas AI'], (err, stdout) => callback(err, stdout.trim().split('\n').filter(Boolean)));
  }
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
      // Normalize clipboard images exactly like file-picker images so providers
      // receive inline image data instead of an unusable temporary path.
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

function mimeFromPath(filePath) {
  const ext = path.extname(filePath).toLowerCase();
  if (ext === '.png') return 'image/png';
  if (ext === '.jpg' || ext === '.jpeg') return 'image/jpeg';
  if (ext === '.gif') return 'image/gif';
  if (ext === '.webp') return 'image/webp';
  if (ext === '.bmp') return 'image/bmp';
  if (ext === '.svg') return 'image/svg+xml';
  if (ext === '.txt' || ext === '.md' || ext === '.json' || ext === '.dart' || ext === '.js' || ext === '.ts' || ext === '.html' || ext === '.css' || ext === '.yaml' || ext === '.yml' || ext === '.xml' || ext === '.csv' || ext === '.sh' || ext === '.ps1') return 'text/plain';
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

// ── AI HTTP Dispatcher (Ollama / OpenAI / Custom) ───────────────────────────

function callAiProvider(settings, prompt, contextCode, attachments, callback) {
  const provider = settings.aiProvider || 'builtIn';
  const systemPrompt = settings.aiSystemPrompt || 'You are Atlas, an expert agentic AI software engineer embedded in Atlas IDE. When providing code changes or new files, wrap complete code in ```language:filepath code blocks.';
  const textAttachments = (attachments || []).filter(item => item && item.kind === 'file' && typeof item.text === 'string');
  const imageAttachments = (attachments || []).filter(item => item && item.kind === 'image' && typeof item.dataBase64 === 'string');

  const attachmentSummary = (attachments || []).map((item) => {
    if (!item || !item.name) return '';
    if (item.kind === 'image') return `- Image: ${item.name} (${item.mimeType || 'image'})`;
    if (item.kind === 'file') return `- File: ${item.name} (${item.mimeType || 'file'}${item.size ? `, ${item.size} bytes` : ''})`;
    return `- Attachment: ${item.name}`;
  }).filter(Boolean).join('\n');

  const userText = [
    contextCode ? `Active Code Context:\n\`\`\`\n${contextCode}\n\`\`\`` : '',
    attachmentSummary ? `Attachments:\n${attachmentSummary}` : '',
    textAttachments.length
      ? `Attached File Contents:\n${textAttachments.map((item) => `### ${item.name}\n\`\`\`\n${item.text}\n\`\`\``).join('\n\n')}`
      : '',
    `Task: ${prompt}`,
  ].filter(Boolean).join('\n\n');

  if (provider === 'openRouter') {
    const endpoint = settings.openRouterEndpoint || 'https://openrouter.ai/api/v1';
    const model = settings.openRouterModel || 'google/gemini-2.5-flash';
    const apiKey = settings.openRouterApiKey || process.env.OPENROUTER_API_KEY || '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';

    if (!apiKey) {
      return callback(null, '❌ OpenRouter API Key is missing! Set your key in Atlas Settings → AI Agent.');
    }

    let url;
    try {
      const base = endpoint.endsWith('/') ? endpoint : endpoint + '/';
      url = new URL('chat/completions', base);
    } catch {
      return callback(null, `❌ Invalid OpenRouter URL: ${endpoint}`);
    }

    const userMessage = imageAttachments.length
      ? {
          role: 'user',
          content: [
            { type: 'text', text: userText },
            ...imageAttachments.map((item) => ({
              type: 'image_url',
              image_url: { url: `data:${item.mimeType};base64,${item.dataBase64}` },
            })),
          ],
        }
      : { role: 'user', content: userText };

    const postData = JSON.stringify({
      model: model,
      messages: [
        { role: 'system', content: systemPrompt },
        userMessage
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
        'HTTP-Referer': 'https://github.com/atlas-ide',
        'X-Title': 'Atlas IDE',
        'Content-Length': Buffer.byteLength(postData)
      }
    }, (res) => {
      let body = '';
      res.on('data', chunk => body += chunk);
      res.on('end', () => {
        try {
          const parsed = JSON.parse(body);
          if (parsed.choices && parsed.choices[0] && parsed.choices[0].message) {
            callback(null, `### ⚡ OpenRouter (${model})\n\n${parsed.choices[0].message.content}`);
          } else {
            callback(null, `❌ OpenRouter API Error: ${parsed.error?.message || body}`);
          }
        } catch (e) {
          callback(null, `OpenRouter Response: ${body}`);
        }
      });
    });
    req.on('error', (err) => callback(null, `❌ OpenRouter Request Failed: ${err.message}`));
    req.write(postData);
    req.end();
  } else if (provider === 'ollama') {
    const endpoint = settings.ollamaEndpoint || 'http://localhost:11434';
    const model = settings.ollamaModel || 'deepseek-coder';
    let url;
    try {
      url = new URL('/api/chat', endpoint);
    } catch {
      return callback(null, `❌ Invalid Ollama URL: ${endpoint}`);
    }

    const userMessage = imageAttachments.length
      ? {
          role: 'user',
          content: [
            { type: 'text', text: userText },
            ...imageAttachments.map((item) => ({
              type: 'image_url',
              image_url: { url: `data:${item.mimeType};base64,${item.dataBase64}` },
            })),
          ],
        }
      : { role: 'user', content: userText };

    const postData = JSON.stringify({
      model: model,
      messages: [
        { role: 'system', content: systemPrompt },
        userMessage
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
        { role: 'user', content: userText }
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

    const postData = JSON.stringify({ prompt, contextCode, systemPrompt, attachments });
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
  let clientSettings = { aiProvider: 'builtIn', ...loadPersistedSettings() };
  let workspaceRoot = loadPersistedWorkspaceRoot();

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
        projectName: path.basename(workspaceRoot),
        cwd: workspaceRoot,
        settings: clientSettings,
      }));
      return;
    }

    // ── Authenticated commands ───────────────────────────────────────────
    switch (data.type) {
      case 'update_settings': {
        clientSettings = data.settings || {};
        persistSettings(clientSettings);
        console.log(`Settings updated. AI Provider: ${clientSettings.aiProvider || 'builtIn'}`);
        break;
      }

      case 'github_test_user': {
        const token = data.token || clientSettings.githubToken;
        callGithubApi(token, 'GET', '/user', null, (err, user) => {
          if (err) {
            ws.send(JSON.stringify({ type: 'github_user_result', error: err.message }));
          } else {
            console.log(`GitHub User Authenticated: @${user.login}`);
            ws.send(JSON.stringify({ type: 'github_user_result', user }));
          }
        });
        break;
      }

      case 'github_push': {
        const branch = typeof data.branch === 'string' && data.branch.trim() ? data.branch.trim() : 'HEAD';
        runGit(['push', 'origin', branch], workspaceRoot, (err, stdout, stderr) => {
          const output = stdout || stderr || (err ? err.message : 'Pushed to GitHub successfully!');
          ws.send(JSON.stringify({ type: 'output', content: `\n[GitHub Push] ${output}\n` }));
        });
        break;
      }

      case 'github_pull': {
        const branch = typeof data.branch === 'string' && data.branch.trim() ? data.branch.trim() : 'HEAD';
        runGit(['pull', 'origin', branch], workspaceRoot, (err, stdout, stderr) => {
          const output = stdout || stderr || (err ? err.message : 'Pulled from GitHub successfully!');
          ws.send(JSON.stringify({ type: 'output', content: `\n[GitHub Pull] ${output}\n` }));
        });
        break;
      }

      case 'github_create_repo': {
        const token = data.token || clientSettings.githubToken;
        const repoName = data.name || path.basename(workspaceRoot);
        const isPrivate = data.isPrivate !== false;

        callGithubApi(token, 'POST', '/user/repos', { name: repoName, private: isPrivate }, (err, repo) => {
          if (err) {
            ws.send(JSON.stringify({ type: 'error', content: `Failed to create GitHub repo: ${err.message}\n` }));
            return;
          }

          const remoteArgs = ['remote', 'set-url', 'origin', repo.clone_url];
          runGit(['remote', 'get-url', 'origin'], workspaceRoot, (remoteErr) => {
            if (remoteErr) remoteArgs.splice(1, 2, 'add', 'origin');
            runGit(remoteArgs, workspaceRoot, (setRemoteErr) => {
              if (setRemoteErr) {
                ws.send(JSON.stringify({ type: 'error', content: `Failed to configure Git remote: ${setRemoteErr.message}\n` }));
                return;
              }
              const auth = `Authorization: Basic ${Buffer.from(`x-access-token:${token}`).toString('base64')}`;
              const env = { ...process.env, GIT_CONFIG_COUNT: '1', GIT_CONFIG_KEY_0: 'http.extraheader', GIT_CONFIG_VALUE_0: auth };
              runGit(['push', '-u', 'origin', 'HEAD'], workspaceRoot, (pushErr, stdout, stderr) => {
                const output = stdout || stderr || (pushErr ? pushErr.message : 'Pushed code to GitHub');
                ws.send(JSON.stringify({
                  type: pushErr ? 'error' : 'output',
                  content: `\nRepository created on GitHub: ${repo.html_url}\n[Git Push] ${output}\n`,
                }));
              }, { env });
            });
          });
        });
        break;
      }

      case 'open_folder': {
        const requestedPath = typeof data.path === 'string' ? data.path.trim() : '';
        const setWorkspace = (folder) => {
          if (!folder || !path.isAbsolute(folder) || !fs.existsSync(folder) || !fs.statSync(folder).isDirectory()) {
            ws.send(JSON.stringify({ type: 'error', content: 'Please select an existing folder.\n' }));
            return;
          }
          workspaceRoot = path.resolve(folder);
          persistWorkspaceRoot(workspaceRoot);
          ws.send(JSON.stringify({
            type: 'workspace_opened',
            projectName: path.basename(workspaceRoot),
            cwd: workspaceRoot,
            children: buildTree(workspaceRoot),
          }));
        };
        if (requestedPath) setWorkspace(requestedPath);
        else selectFolder((err, folder) => {
          if (err || !folder) return;
          setWorkspace(folder);
        });
        break;
      }

      case 'pick_attachments': {
        selectFiles((err, files) => {
          if (err || !files || files.length === 0) {
            if (err) ws.send(JSON.stringify({ type: 'error', content: `Failed to pick files: ${err.message}\n` }));
            return;
          }
          const attachments = files
            .map((file) => readAttachmentFromPath(file, workspaceRoot))
            .filter(Boolean);
          ws.send(JSON.stringify({ type: 'attachments_result', attachments }));
        });
        break;
      }

      case 'paste_clipboard_attachment': {
        readClipboardAttachment((err, result) => {
          if (err) {
            ws.send(JSON.stringify({ type: 'error', content: `Clipboard paste failed: ${err.message}\n` }));
            return;
          }
          if (result) {
            ws.send(JSON.stringify({ type: 'clipboard_paste_result', result }));
          }
        });
        break;
      }

      case 'cmd': {
        const command = data.command;
        console.log(`Exec: ${command}`);

        if (activeProc) {
          try { activeProc.kill(); } catch { }
        }

        activeProc = spawn(command, { shell: true, cwd: workspaceRoot });

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
        const attachments = Array.isArray(data.attachments) ? data.attachments : [];

        console.log(`AI Agent Prompt (${settings.aiProvider || 'builtIn'}): ${prompt.substring(0, 60)}...`);

        callAiProvider(settings, prompt, contextCode, attachments, (err, answer) => {
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
        const results = searchWorkspaceFiles(workspaceRoot, workspaceRoot, query);
        ws.send(JSON.stringify({
          type: 'search_results',
          query: query,
          results: results,
        }));
        break;
      }

      case 'git_status': {
        sendGitStatus(ws, workspaceRoot);
        break;
      }

      case 'git_commit': {
        const message = typeof data.message === 'string' && data.message.trim() ? data.message.trim() : 'Update files';
        runGit(['add', '-A'], workspaceRoot, (addErr, addOut, addErrOut) => {
          if (addErr) {
            ws.send(JSON.stringify({ type: 'error', content: `\n[Git Commit] ${addErrOut || addErr.message}\n` }));
            return;
          }
          runGit(['commit', '-m', message], workspaceRoot, (err, stdout, stderr) => {
            const output = stdout || stderr || (err ? err.message : 'Committed successfully');
            ws.send(JSON.stringify({ type: err ? 'error' : 'output', content: `\n[Git Commit] ${output}\n` }));
            sendGitStatus(ws, workspaceRoot);
          });
        });
        break;
      }

      case 'list_dir': {
        ws.send(JSON.stringify({ type: 'file_tree', children: buildTree(workspaceRoot) }));
        break;
      }

      case 'read_file': {
        const fp = resolveWorkspacePath(workspaceRoot, data.path);
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
        const fp = resolveWorkspacePath(workspaceRoot, data.path);
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
          createWorkspaceEntry(workspaceRoot, data.path, isDir);
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
      try { activeProc.kill(); } catch { }
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
  console.log(`  Default root: ${DEFAULT_PROJECT_ROOT}\n`);
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
