const WebSocket = require('ws');
const path = require('path');
const os = require('os');

// Engine modules
const settingsModule = require('./engine/settings');
const workspaceModule = require('./engine/workspace');
const filesystemModule = require('./engine/filesystem');
const searchModule = require('./engine/search');
const gitModule = require('./engine/git');
const terminalModule = require('./engine/terminal');
const aiProvidersModule = require('./engine/ai_providers');
const { PermissionManager } = require('./engine/permissions');
const { initializeMcpTools } = require('./engine/mcp/init');
const { AgentLoop } = require('./engine/agent/agent_loop');

const PORT = process.env.PORT ? parseInt(process.env.PORT, 10) : 8080;
const ENGINE_TOKEN = process.env.ATLAS_ENGINE_TOKEN || 'dev-token';

// Initialize MCP tools globally
const toolRegistry = initializeMcpTools();

// Active connection state
function handleConnection(ws) {
  let authenticated = false;
  let activeProc = null;
  let activeAgentLoop = null;
  let pendingDiffResolver = null;

  let clientSettings = { aiProvider: 'builtIn', ...settingsModule.loadPersistedSettings() };
  let workspaceRoot = workspaceModule.loadPersistedWorkspaceRoot();
  const permissionManager = new PermissionManager(clientSettings.agentPermissionPolicy || 'approve_write');

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
        settingsModule.persistSettings(clientSettings);
        permissionManager.setPolicy(clientSettings.agentPermissionPolicy || 'approve_write');
        console.log(`Settings updated. AI Provider: ${clientSettings.aiProvider || 'builtIn'}`);
        break;
      }

      // ── GitHub operations ────────────────────────────────────────────────
      case 'github_test_user': {
        const token = data.token || clientSettings.githubToken;
        gitModule.callGithubApi(token, 'GET', '/user', null, (err, user) => {
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
        gitModule.runGit(['push', 'origin', branch], workspaceRoot, (err, stdout, stderr) => {
          const output = stdout || stderr || (err ? err.message : 'Pushed to GitHub successfully!');
          ws.send(JSON.stringify({ type: 'output', content: `\n[GitHub Push] ${output}\n` }));
        });
        break;
      }

      case 'github_pull': {
        const branch = typeof data.branch === 'string' && data.branch.trim() ? data.branch.trim() : 'HEAD';
        gitModule.runGit(['pull', 'origin', branch], workspaceRoot, (err, stdout, stderr) => {
          const output = stdout || stderr || (err ? err.message : 'Pulled from GitHub successfully!');
          ws.send(JSON.stringify({ type: 'output', content: `\n[GitHub Pull] ${output}\n` }));
        });
        break;
      }

      case 'github_create_repo': {
        const token = data.token || clientSettings.githubToken;
        const repoName = data.name || path.basename(workspaceRoot);
        const isPrivate = data.isPrivate !== false;

        gitModule.callGithubApi(token, 'POST', '/user/repos', { name: repoName, private: isPrivate }, (err, repo) => {
          if (err) {
            ws.send(JSON.stringify({ type: 'error', content: `Failed to create GitHub repo: ${err.message}\n` }));
            return;
          }

          const remoteArgs = ['remote', 'set-url', 'origin', repo.clone_url];
          gitModule.runGit(['remote', 'get-url', 'origin'], workspaceRoot, (remoteErr) => {
            if (remoteErr) remoteArgs.splice(1, 2, 'add', 'origin');
            gitModule.runGit(remoteArgs, workspaceRoot, (setRemoteErr) => {
              if (setRemoteErr) {
                ws.send(JSON.stringify({ type: 'error', content: `Failed to configure Git remote: ${setRemoteErr.message}\n` }));
                return;
              }
              const auth = `Authorization: Basic ${Buffer.from(`x-access-token:${token}`).toString('base64')}`;
              const env = { ...process.env, GIT_CONFIG_COUNT: '1', GIT_CONFIG_KEY_0: 'http.extraheader', GIT_CONFIG_VALUE_0: auth };
              gitModule.runGit(['push', '-u', 'origin', 'HEAD'], workspaceRoot, (pushErr, stdout, stderr) => {
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

      // ── Workspace & File pickers ──────────────────────────────────────────
      case 'open_folder': {
        const requestedPath = typeof data.path === 'string' ? data.path.trim() : '';
        const setWorkspace = (folder) => {
          if (!folder || !path.isAbsolute(folder) || !require('fs').existsSync(folder) || !require('fs').statSync(folder).isDirectory()) {
            ws.send(JSON.stringify({ type: 'error', content: 'Please select an existing folder.\n' }));
            return;
          }
          workspaceRoot = path.resolve(folder);
          workspaceModule.persistWorkspaceRoot(workspaceRoot);
          ws.send(JSON.stringify({
            type: 'workspace_opened',
            projectName: path.basename(workspaceRoot),
            cwd: workspaceRoot,
            children: filesystemModule.buildTree(workspaceRoot),
          }));
        };
        if (requestedPath) setWorkspace(requestedPath);
        else workspaceModule.selectFolder((err, folder) => {
          if (err || !folder) return;
          setWorkspace(folder);
        });
        break;
      }

      case 'pick_attachments': {
        workspaceModule.selectFiles((err, files) => {
          if (err || !files || files.length === 0) {
            if (err) ws.send(JSON.stringify({ type: 'error', content: `Failed to pick files: ${err.message}\n` }));
            return;
          }
          const attachments = files
            .map((file) => filesystemModule.readAttachmentFromPath(file, workspaceRoot))
            .filter(Boolean);
          ws.send(JSON.stringify({ type: 'attachments_result', attachments }));
        });
        break;
      }

      case 'paste_clipboard_attachment': {
        filesystemModule.readClipboardAttachment((err, result) => {
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

      // ── Terminal Execution ────────────────────────────────────────────────
      case 'cmd': {
        const command = data.command;
        console.log(`Exec: ${command}`);

        if (activeProc) {
          terminalModule.killProcess(activeProc);
        }

        activeProc = terminalModule.executeCommand(command, workspaceRoot, {
          onStdout: (text) => ws.send(JSON.stringify({ type: 'output', content: text })),
          onStderr: (text) => ws.send(JSON.stringify({ type: 'error', content: text })),
          onClose: (code) => {
            activeProc = null;
            ws.send(JSON.stringify({ type: 'exit', code }));
          },
          onError: (err) => {
            activeProc = null;
            ws.send(JSON.stringify({ type: 'error', content: err.toString() }));
          },
        });
        break;
      }

      case 'kill_cmd': {
        if (activeProc) {
          console.log('Terminating active process...');
          terminalModule.killProcess(activeProc);
          activeProc = null;
          ws.send(JSON.stringify({ type: 'output', content: '\n^C [Process terminated by user]\n' }));
        }
        break;
      }

      // ── Simple AI Chat Prompt (Backwards Compatible) ─────────────────────
      case 'ai_prompt': {
        const prompt = data.prompt || '';
        const contextCode = data.contextCode || '';
        const settings = data.settings || clientSettings;
        const attachments = Array.isArray(data.attachments) ? data.attachments : [];

        console.log(`AI Agent Prompt (${settings.aiProvider || 'builtIn'}): ${prompt.substring(0, 60)}...`);

        aiProvidersModule.callAiProvider(settings, prompt, contextCode, attachments, (err, answer) => {
          ws.send(JSON.stringify({
            type: 'ai_response',
            prompt: prompt,
            content: answer,
          }));
        });
        break;
      }

      // ── Atlas Agent / MCP Loop Protocol ──────────────────────────────────
      case 'agent_start': {
        const prompt = data.prompt || '';
        const ideContext = data.ideContext || {};
        const settings = data.settings || clientSettings;

        console.log(`Starting Atlas Agent Loop: "${prompt.substring(0, 50)}..."`);

        if (activeAgentLoop) {
          activeAgentLoop.cancel();
        }

        activeAgentLoop = new AgentLoop({
          workspaceRoot,
          permissionManager,
          toolRegistry,
          settings,
          callbacks: {
            onProgress: (status) => {
              ws.send(JSON.stringify({ type: 'agent_progress', status }));
            },
            onToolCall: (info) => {
              ws.send(JSON.stringify({ type: 'agent_tool_call', ...info }));
            },
            onToolResult: (info) => {
              ws.send(JSON.stringify({ type: 'agent_tool_result', ...info }));
            },
            onRequestApproval: (approvalReq) => {
              return new Promise((resolve) => {
                const pendingPromise = permissionManager.createPendingApproval(
                  approvalReq.requestId,
                  approvalReq.toolName,
                  approvalReq.args,
                  approvalReq.category
                );

                ws.send(JSON.stringify({
                  type: 'agent_approval_request',
                  requestId: approvalReq.requestId,
                  toolName: approvalReq.toolName,
                  args: approvalReq.args,
                  category: approvalReq.category,
                }));

                pendingPromise.then(resolve);
              });
            },
            onDiffProposal: (diffInfo) => {
              return new Promise((resolve) => {
                pendingDiffResolver = resolve;
                ws.send(JSON.stringify({
                  type: 'agent_diff_proposal',
                  path: diffInfo.path,
                  diff: diffInfo.diff,
                  hunks: diffInfo.hunks,
                }));
              });
            },
            onComplete: (result) => {
              activeAgentLoop = null;
              ws.send(JSON.stringify({
                type: 'agent_response',
                content: result.content,
                iterations: result.iterations,
              }));
            },
            onError: (err) => {
              activeAgentLoop = null;
              ws.send(JSON.stringify({ type: 'error', content: `Agent error: ${err}` }));
            },
          },
        });

        activeAgentLoop.run(prompt, ideContext);
        break;
      }

      case 'agent_cancel': {
        if (activeAgentLoop) {
          activeAgentLoop.cancel();
          activeAgentLoop = null;
          ws.send(JSON.stringify({ type: 'agent_progress', status: 'Agent cancelled by user.' }));
        }
        break;
      }

      case 'agent_approval_response': {
        const requestId = data.requestId;
        const granted = !!data.granted;
        if (granted) {
          permissionManager.grantPending(requestId);
        } else {
          permissionManager.denyPending(requestId, data.reason || 'User rejected permission request');
        }
        break;
      }

      case 'agent_diff_decision': {
        const accepted = !!data.accepted;
        if (pendingDiffResolver) {
          const resolve = pendingDiffResolver;
          pendingDiffResolver = null;
          resolve(accepted);
        }
        break;
      }

      // ── Workspace Filesystem API ──────────────────────────────────────────
      case 'search_files': {
        const query = data.query || '';
        const results = searchModule.searchWorkspaceFiles(workspaceRoot, workspaceRoot, query);
        ws.send(JSON.stringify({
          type: 'search_results',
          query: query,
          results: results,
        }));
        break;
      }

      case 'git_status': {
        gitModule.sendGitStatus(ws, workspaceRoot);
        break;
      }

      case 'git_commit': {
        const message = typeof data.message === 'string' && data.message.trim() ? data.message.trim() : 'Update files';
        gitModule.runGit(['add', '-A'], workspaceRoot, (addErr, addOut, addErrOut) => {
          if (addErr) {
            ws.send(JSON.stringify({ type: 'error', content: `\n[Git Commit] ${addErrOut || addErr.message}\n` }));
            return;
          }
          gitModule.runGit(['commit', '-m', message], workspaceRoot, (err, stdout, stderr) => {
            const output = stdout || stderr || (err ? err.message : 'Committed successfully');
            ws.send(JSON.stringify({ type: err ? 'error' : 'output', content: `\n[Git Commit] ${output}\n` }));
            gitModule.sendGitStatus(ws, workspaceRoot);
          });
        });
        break;
      }

      case 'list_dir': {
        ws.send(JSON.stringify({ type: 'file_tree', children: filesystemModule.buildTree(workspaceRoot) }));
        break;
      }

      case 'read_file': {
        try {
          const content = filesystemModule.readFile(workspaceRoot, data.path);
          ws.send(JSON.stringify({ type: 'file_content', path: data.path, content }));
        } catch (e) {
          ws.send(JSON.stringify({ type: 'file_content', path: data.path, content: `[Error: ${e.message}]` }));
        }
        break;
      }

      case 'write_file': {
        try {
          filesystemModule.writeFile(workspaceRoot, data.path, data.content);
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
          filesystemModule.createWorkspaceEntry(workspaceRoot, data.path, isDir);
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
      terminalModule.killProcess(activeProc);
    }
    if (activeAgentLoop) {
      activeAgentLoop.cancel();
    }
    console.log('Client disconnected.');
  });
}

// ── Start Server ────────────────────────────────────────────────────────────

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
  console.log(`  Default root: ${workspaceModule.DEFAULT_PROJECT_ROOT}\n`);
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
