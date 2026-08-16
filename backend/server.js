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
const { ConversationSessionStore, isValidConversationSessionId } = require('./engine/agent/conversation_session');
const { isLoopbackHost, validateEngineConfig } = require('./engine/security');

const PORT = process.env.PORT ? parseInt(process.env.PORT, 10) : 8080;
const { host: ENGINE_HOST, token: ENGINE_TOKEN } = validateEngineConfig({
  host: process.env.ATLAS_ENGINE_HOST || '127.0.0.1',
  token: process.env.ATLAS_ENGINE_TOKEN,
});

// Initialize MCP tools globally
const toolRegistry = initializeMcpTools();
const conversationSessions = new ConversationSessionStore();

// Active connection state
function handleConnection(ws) {
  let authenticated = false;
  let activeProc = null;
  let terminalSession = null;
  let activeAgentLoop = null;
  let activeConversationSession = null;
  let pendingDiffResolver = null;
  // Old clients do not send a session id. They still retain context for this
  // WebSocket connection, while current clients retain it across reconnects.
  const connectionSessionId = require('crypto').randomUUID();

  let clientSettings = { aiProvider: 'builtIn', ...settingsModule.loadPersistedSettings() };
  let workspaceRoot = workspaceModule.loadPersistedWorkspaceRoot();
  const permissionManager = new PermissionManager(clientSettings.agentPermissionPolicy || 'approve_write');

  const startTerminal = (options = {}) => {
    if (terminalSession) return terminalSession;
    terminalSession = terminalModule.createTerminal({
      cwd: workspaceRoot,
      cols: options.cols,
      rows: options.rows,
      onData: (content) => ws.send(JSON.stringify({ type: 'terminal_data', content })),
      onExit: ({ exitCode, signal }) => {
        terminalSession = null;
        ws.send(JSON.stringify({ type: 'terminal_exit', exitCode, signal }));
      },
    });
    ws.send(JSON.stringify({ type: 'terminal_ready' }));
    return terminalSession;
  };

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
        const setWorkspace = (folder, { trust = false } = {}) => {
          if (!folder || !path.isAbsolute(folder) || !require('fs').existsSync(folder) || !require('fs').statSync(folder).isDirectory()) {
            ws.send(JSON.stringify({ type: 'error', content: 'Please select an existing folder.\n' }));
            return;
          }
          if (!trust && !workspaceModule.isTrustedWorkspace(folder)) {
            ws.send(JSON.stringify({
              type: 'error',
              content: 'Workspace is not approved on this engine. Select it with Open Folder on the engine machine first.\n',
            }));
            return;
          }
          workspaceRoot = path.resolve(folder);
          workspaceModule.persistWorkspaceRoot(workspaceRoot, { trust });
          terminalModule.closeTerminal(terminalSession);
          terminalSession = null;
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
          setWorkspace(folder, { trust: true });
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
      case 'terminal_open': {
        startTerminal(data);
        break;
      }

      case 'terminal_input': {
        const input = typeof data.data === 'string' ? data.data : '';
        if (input) startTerminal().write(input);
        break;
      }

      case 'terminal_resize': {
        if (terminalSession) {
          terminalSession.resize(
            Math.max(20, Number(data.cols) || 100),
            Math.max(5, Number(data.rows) || 30),
          );
        }
        break;
      }

      case 'terminal_close': {
        terminalModule.closeTerminal(terminalSession);
        terminalSession = null;
        break;
      }

      case 'cmd': {
        const command = data.command;
        console.log(`Exec: ${command}`);
        startTerminal().write(`${command}\r`);
        break;
      }

      case 'kill_cmd': {
        if (terminalSession) {
          terminalSession.write('\u0003');
        } else if (activeProc) {
          terminalModule.killProcess(activeProc);
          activeProc = null;
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
        const sessionId = isValidConversationSessionId(data.sessionId)
          ? data.sessionId
          : connectionSessionId;
        const conversationSession = conversationSessions.getOrCreate(sessionId, workspaceRoot);

        console.log(`Starting Atlas Agent Loop: "${prompt.substring(0, 50)}..."`);

        if (activeAgentLoop) {
          ws.send(JSON.stringify({
            type: 'error',
            content: 'An agent task is already running in this conversation. Wait for it to finish or cancel it before sending another message.\n',
          }));
          break;
        }
        if (!conversationSession.startRun()) {
          ws.send(JSON.stringify({
            type: 'error',
            content: 'This conversation is already running on another connection. Wait for it to finish before sending another message.\n',
          }));
          break;
        }
        activeConversationSession = conversationSession;

        activeAgentLoop = new AgentLoop({
          workspaceRoot,
          permissionManager,
          toolRegistry,
          settings,
          conversation: conversationSession.conversation,
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
              // Save the conversation history back to the session for continuity
              conversationSession.conversation = activeAgentLoop.conversation;
              conversationSession.finishRun();
              if (activeConversationSession === conversationSession) {
                activeAgentLoop = null;
                activeConversationSession = null;
              }
              ws.send(JSON.stringify({
                type: 'agent_response',
                content: result.content,
                iterations: result.iterations,
              }));
            },
            onError: (err) => {
              conversationSession.finishRun();
              if (activeConversationSession === conversationSession) {
                activeAgentLoop = null;
                activeConversationSession = null;
              }
              ws.send(JSON.stringify({ type: 'error', content: `Agent error: ${err}` }));
            },
          },
        });

        activeAgentLoop.run(prompt, ideContext).catch((error) => {
          const message = `Agent failed: ${error.message}. Your conversation was preserved; you can retry.`;
          conversationSession.conversation.push({ role: 'assistant', content: message });
          conversationSession.finishRun();
          if (activeConversationSession === conversationSession) {
            activeAgentLoop = null;
            activeConversationSession = null;
          }
          ws.send(JSON.stringify({ type: 'agent_response', content: message, iterations: 0 }));
        });
        break;
      }

      case 'agent_cancel': {
        if (activeAgentLoop) {
          activeAgentLoop.cancel();
          activeAgentLoop = null;
          activeConversationSession?.finishRun();
          activeConversationSession = null;
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

      case 'git_diff': {
        gitModule.sendGitDiff(ws, workspaceRoot, data.path, !!data.staged);
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
    terminalModule.closeTerminal(terminalSession);
    if (activeProc) {
      terminalModule.killProcess(activeProc);
    }
    if (activeAgentLoop) {
      activeAgentLoop.cancel();
    }
    activeConversationSession?.finishRun();
    console.log('Client disconnected.');
  });
}

// ── Start Server ────────────────────────────────────────────────────────────

const wss = new WebSocket.Server({ port: PORT, host: ENGINE_HOST });

wss.on('listening', () => {
  console.log(`\n======================================================`);
  console.log(`  Atlas Engine listening on ${ENGINE_HOST}:${PORT}`);
  if (ENGINE_TOKEN) {
    console.log(`  Session Token: ${ENGINE_TOKEN}`);
  }
  if (!isLoopbackHost(ENGINE_HOST)) {
    const nets = os.networkInterfaces();
    console.log(`\n  iPad / Remote Connection Endpoints:`);
    for (const name of Object.keys(nets)) {
      for (const net of nets[name]) {
        if (net.family === 'IPv4' && !net.internal) {
          console.log(`    ws://${net.address}:${PORT}`);
        }
      }
    }
  }
  console.log(`======================================================`);
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
