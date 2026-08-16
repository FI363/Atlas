import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../state/agent_state.dart';

/// WebSocket client for the companion Atlas backend engine.
///
/// Handles authentication, terminal commands, file I/O, process termination,
/// search, git operations, AI Agent prompt messages, and MCP tool-calling agent loops.
class EngineClient extends ChangeNotifier {
  WebSocketChannel? _channel;
  bool _isConnected = false;
  int _connectionId = 0;
  Timer? _reconnectTimer;
  String? _lastEngineUrl;
  String? _lastEngineToken;
  bool _manualDisconnect = true;
  int _reconnectAttempts = 0;
  bool _hasEstablishedConnection = false;
  bool _pendingReconnected = false;

  static const _maxReconnectAttempts = 5;
  final String _agentSessionId = _createAgentSessionId();

  static String _createAgentSessionId() {
    final random = Random.secure();
    final timestamp = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final entropy = List<int>.generate(16, (_) => random.nextInt(256));
    return 'atlas_${timestamp}_${base64UrlEncode(entropy).replaceAll('=', '')}';
  }

  // Agent State
  final AgentState agentState = AgentState();

  // Terminal output stream
  final List<String> _terminalOutput = [];
  bool _terminalReady = false;

  // AI Agent message history
  final List<Map<String, dynamic>> _aiMessages = [
    {
      'isUser': false,
      'content':
          'Hello! I am your Atlas AI Coding Agent with MCP support. Ask me a question or assign me a coding task!',
    },
  ];

  // Search results stream
  List<Map<String, dynamic>> _searchResults = [];
  String _searchQuery = '';

  // AI thinking state
  bool _isAiThinking = false;

  // Git status data
  String _gitBranch = 'main';
  List<Map<String, dynamic>> _gitFiles = [];
  String? _gitDiffPath;
  String _gitDiff = '';
  bool _gitDiffIsStaged = false;
  Map<String, dynamic>? _githubUser;

  // File system data
  List<Map<String, dynamic>> _fileTree = [];
  final Map<String, String> _fileContents = {};
  String? _lastSavedFilePath;
  bool _workspaceChanged = false;
  bool _workspaceOpened = false;
  List<Map<String, dynamic>> _pendingAttachments = [];
  Map<String, dynamic>? _pendingClipboardPaste;
  Map<String, dynamic>? _pendingSettings;

  String _projectName = 'atlas';
  String _cwd = '';

  bool get isConnected => _isConnected;
  String get projectName => _projectName;
  String get cwd => _cwd;
  List<String> get terminalOutput => List.unmodifiable(_terminalOutput);
  List<Map<String, dynamic>> get aiMessages => List.unmodifiable(_aiMessages);
  bool get isAiThinking => _isAiThinking;
  List<Map<String, dynamic>> get searchResults =>
      List.unmodifiable(_searchResults);
  String get searchQuery => _searchQuery;
  String get gitBranch => _gitBranch;
  List<Map<String, dynamic>> get gitFiles => List.unmodifiable(_gitFiles);
  String? get gitDiffPath => _gitDiffPath;
  String get gitDiff => _gitDiff;
  bool get gitDiffIsStaged => _gitDiffIsStaged;
  Map<String, dynamic>? get githubUser => _githubUser;
  List<Map<String, dynamic>> get fileTree => _fileTree;

  /// Get cached file content (or null if not loaded yet).
  String? getFileContent(String path) => _fileContents[path];

  /// Returns and clears the most recently confirmed save path.
  String? takeLastSavedFilePath() {
    final p = _lastSavedFilePath;
    _lastSavedFilePath = null;
    return p;
  }

  /// Returns whether the engine confirmed a file-system change since last read.
  bool takeWorkspaceChanged() {
    final changed = _workspaceChanged;
    _workspaceChanged = false;
    return changed;
  }

  bool takeWorkspaceOpened() {
    final opened = _workspaceOpened;
    _workspaceOpened = false;
    return opened;
  }

  List<Map<String, dynamic>> takePendingAttachments() {
    final attachments = List<Map<String, dynamic>>.from(_pendingAttachments);
    _pendingAttachments = [];
    return attachments;
  }

  Map<String, dynamic>? takeClipboardPasteResult() {
    final result = _pendingClipboardPaste;
    _pendingClipboardPaste = null;
    return result;
  }

  Map<String, dynamic>? takePendingSettings() {
    final result = _pendingSettings;
    _pendingSettings = null;
    return result;
  }

  /// Returns whether an already-established engine connection was restored.
  /// This lets workspace state refresh remote data without discarding drafts.
  bool takeReconnected() {
    final reconnected = _pendingReconnected;
    _pendingReconnected = false;
    return reconnected;
  }

  // ── Connection ──────────────────────────────────────────────────────────

  Future<void> connect({required String url, required String token}) async {
    if (token.isEmpty) {
      _manualDisconnect = true;
      _log(
        'Engine token is missing. Rebuild with --dart-define=ATLAS_ENGINE_TOKEN=...\n',
      );
      return;
    }

    _lastEngineUrl = url;
    _lastEngineToken = token;
    _manualDisconnect = false;
    _reconnectAttempts = 0;
    _reconnectTimer?.cancel();
    await _openConnection();
  }

  Future<void> _openConnection() async {
    final url = _lastEngineUrl;
    final token = _lastEngineToken;
    if (_manualDisconnect || url == null || token == null) return;

    try {
      final connectionId = ++_connectionId;
      await _channel?.sink.close();
      _channel = WebSocketChannel.connect(Uri.parse(url));

      _channel!.stream.listen(
        _handleMessage,
        onDone: () {
          _handleConnectionLost(connectionId, 'Disconnected from engine.\n');
        },
        onError: (error) {
          _handleConnectionLost(connectionId, 'Connection error: $error\n');
        },
      );

      await _channel!.ready;
      if (connectionId != _connectionId) return;
      _isConnected = true;
      _send({'type': 'auth', 'token': token});
      notifyListeners();
    } catch (e) {
      _isConnected = false;
      _log('Failed to connect: $e\n');
      notifyListeners();
      _scheduleReconnect();
    }
  }

  void disconnect() {
    _manualDisconnect = true;
    _reconnectTimer?.cancel();
    _connectionId++;
    _channel?.sink.close();
    _isConnected = false;
    notifyListeners();
  }

  void _handleConnectionLost(int connectionId, String message) {
    if (connectionId != _connectionId || _manualDisconnect) return;
    _isConnected = false;
    _isAiThinking = false;
    agentState.cancelAgent();
    _log(message);
    notifyListeners();
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_manualDisconnect || _reconnectTimer?.isActive == true) return;
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      _log('Unable to reconnect. Use Connect to try again.\n');
      return;
    }

    final seconds = 1 << _reconnectAttempts;
    _reconnectAttempts++;
    _log('Reconnecting in $seconds second${seconds == 1 ? '' : 's'}...\n');
    _reconnectTimer = Timer(Duration(seconds: seconds), () {
      _openConnection();
    });
  }

  // ── Settings sync ──────────────────────────────────────────────────────

  void sendSettings(Map<String, dynamic> settingsPayload) {
    if (_isConnected) {
      _send({'type': 'update_settings', 'settings': settingsPayload});
    }
  }

  // ── Terminal Commands ──────────────────────────────────────────────────

  void runCommand(String command) {
    if (!_isConnected) {
      _log('Not connected to engine.\n');
      return;
    }
    if (command.trim().toLowerCase() == 'cls' ||
        command.trim().toLowerCase() == 'clear') {
      clearTerminal();
      return;
    }
    _send({'type': 'terminal_input', 'data': '$command\r'});
  }

  void killProcess() {
    if (_isConnected) {
      _send({'type': 'terminal_input', 'data': '\u0003'});
    }
  }

  void resizeTerminal({required int cols, required int rows}) {
    if (_isConnected && _terminalReady) {
      _send({'type': 'terminal_resize', 'cols': cols, 'rows': rows});
    }
  }

  void clearTerminal() {
    _terminalOutput.clear();
    notifyListeners();
  }

  // ── AI Agent Communication ─────────────────────────────────────────────

  void sendAiPrompt(
    String prompt, {
    Map<String, dynamic>? workspaceContext,
    Map<String, dynamic>? settingsPayload,
    List<Map<String, dynamic>> attachments = const [],
    bool useAgentMode = true,
  }) {
    _aiMessages.add({'isUser': true, 'content': prompt});
    _isAiThinking = true;
    notifyListeners();

    if (!_isConnected) {
      _aiMessages.add({
        'isUser': false,
        'content':
            'Engine disconnected. Please start backend server to run AI agent queries.',
      });
      _isAiThinking = false;
      notifyListeners();
      return;
    }

    if (useAgentMode) {
      if (!agentState.isAgentRunning) {
        agentState.startAgent(prompt);
        _isAiThinking = true;
        notifyListeners();
      }
      _send({
        'type': 'agent_start',
        'sessionId': _agentSessionId,
        'prompt': prompt,
        'ideContext': workspaceContext ?? {},
        'settings': settingsPayload ?? {},
      });
    } else {
      _send({
        'type': 'ai_prompt',
        'prompt': prompt,
        'workspaceContext': workspaceContext ?? {},
        'settings': settingsPayload ?? {},
        'attachments': attachments,
      });
    }
  }

  void cancelAgent() {
    if (_isConnected) {
      _send({'type': 'agent_cancel'});
    }
    agentState.cancelAgent();
    _isAiThinking = false;
    notifyListeners();
  }

  void respondToApproval(String requestId, bool granted, {String? reason}) {
    if (_isConnected) {
      _send({
        'type': 'agent_approval_response',
        'requestId': requestId,
        'granted': granted,
        'reason': reason,
      });
    }
    agentState.clearApproval();
  }

  void respondToDiff(bool accepted) {
    if (_isConnected) {
      _send({'type': 'agent_diff_decision', 'accepted': accepted});
    }
    agentState.clearDiff();
  }

  // ── Workspace Search & Git ──────────────────────────────────────────────

  void searchWorkspace(String query) {
    _searchQuery = query;
    if (_isConnected) {
      _send({'type': 'search_files', 'query': query});
    }
  }

  void fetchGitStatus() {
    if (_isConnected) {
      _send({'type': 'git_status'});
    }
  }

  void commitGit(String message) {
    if (_isConnected) {
      _send({'type': 'git_commit', 'message': message});
    }
  }

  void requestGitDiff(String filePath, {bool staged = false}) {
    if (_isConnected) {
      _gitDiffPath = null;
      _gitDiff = '';
      _send({'type': 'git_diff', 'path': filePath, 'staged': staged});
    }
  }

  void testGithubToken(String token) {
    if (_isConnected) _send({'type': 'github_test_user', 'token': token});
  }

  void pushGithub(String branch) {
    if (_isConnected) _send({'type': 'github_push', 'branch': branch});
  }

  void pullGithub(String branch) {
    if (_isConnected) _send({'type': 'github_pull', 'branch': branch});
  }

  void createGithubRepository({
    required String name,
    required bool isPrivate,
    required String token,
  }) {
    if (_isConnected) {
      _send({
        'type': 'github_create_repo',
        'name': name,
        'isPrivate': isPrivate,
        'token': token,
      });
    }
  }

  // ── File System ────────────────────────────────────────────────────────

  void requestFileTree() {
    if (_isConnected) _send({'type': 'list_dir'});
  }

  void requestFileContent(String filePath) {
    if (_isConnected) _send({'type': 'read_file', 'path': filePath});
  }

  void saveFile(String filePath, String content) {
    if (!_isConnected) {
      _log('Cannot save: not connected.\n');
      return;
    }
    _send({'type': 'write_file', 'path': filePath, 'content': content});
  }

  void createFile(String path) => _createEntry('create_file', path);
  void createDirectory(String path) => _createEntry('create_directory', path);
  void openFolder([String? path]) {
    if (path != null) {
      _send({'type': 'open_folder', 'path': path});
    } else {
      _send({'type': 'open_folder'});
    }
  }

  void pickAttachments() {
    if (_isConnected) _send({'type': 'pick_attachments'});
  }

  void pasteClipboardAttachment() {
    if (_isConnected) _send({'type': 'paste_clipboard_attachment'});
  }

  // ── Internals ─────────────────────────────────────────────────────────

  void _createEntry(String type, String path) {
    if (!_isConnected) {
      _log('Cannot create entry: not connected.\n');
      return;
    }
    _send({'type': type, 'path': path});
  }

  /// Add a message to the AI chat (user or system).
  void addAiMessage({required bool isUser, required String content}) {
    _aiMessages.add({'isUser': isUser, 'content': content});
    notifyListeners();
  }

  void _send(Map<String, dynamic> payload) {
    _channel?.sink.add(jsonEncode(payload));
  }

  void _handleMessage(dynamic rawData) {
    try {
      final data = jsonDecode(rawData as String);
      final type = data['type'] as String?;

      switch (type) {
        case 'system':
          _reconnectAttempts = 0;
          _terminalReady = false;
          if (_hasEstablishedConnection) _pendingReconnected = true;
          _hasEstablishedConnection = true;
          if (data['projectName'] != null) {
            _projectName = data['projectName'] as String;
          }
          if (data['cwd'] != null) {
            _cwd = data['cwd'] as String;
          }
          if (data['settings'] is Map<String, dynamic>) {
            _pendingSettings = Map<String, dynamic>.from(
              data['settings'] as Map,
            );
          }
          _log('[SYSTEM] ${data['message']}\n');
          _send({'type': 'terminal_open'});
          return;
        case 'terminal_ready':
          _terminalReady = true;
          return;
        case 'terminal_data':
          _log(data['content'] as String? ?? '');
          return;
        case 'terminal_exit':
          _terminalReady = false;
          _log('[Terminal exited with code ${data['exitCode']}]\n');
          return;
        case 'output':
          _log(data['content'] as String);
          return;
        case 'error':
          _log('[ERROR] ${data['content']}');
          _isAiThinking = false;
          notifyListeners();
          return;
        case 'exit':
          _log('[Process exited with code ${data['code']}]\n');
          return;
        case 'ai_response':
          _isAiThinking = false;
          _aiMessages.add({
            'isUser': false,
            'content': data['content']?.toString() ?? '',
          });
          notifyListeners();
          return;

        // ── Agent Messages ──────────────────────────────────────────────────
        case 'agent_progress':
          agentState.updateProgress(data['status'] as String? ?? '');
          notifyListeners();
          return;
        case 'agent_tool_call':
          agentState.addToolCall(Map<String, dynamic>.from(data as Map));
          notifyListeners();
          return;
        case 'agent_tool_result':
          agentState.completeToolCall(Map<String, dynamic>.from(data as Map));
          notifyListeners();
          return;
        case 'agent_approval_request':
          agentState.requestApproval(Map<String, dynamic>.from(data as Map));
          notifyListeners();
          return;
        case 'agent_diff_proposal':
          agentState.proposeDiff(Map<String, dynamic>.from(data as Map));
          notifyListeners();
          return;
        case 'agent_response':
          _isAiThinking = false;
          agentState.finishAgent(data['content'] as String? ?? '');
          _aiMessages.add({
            'isUser': false,
            'content': data['content'] as String? ?? '',
          });
          notifyListeners();
          return;

        case 'search_results':
          _searchResults = List<Map<String, dynamic>>.from(data['results']);
          notifyListeners();
          return;
        case 'git_status_result':
          _gitBranch = data['branch'] as String? ?? 'main';
          _gitFiles = List<Map<String, dynamic>>.from(data['files'] ?? []);
          notifyListeners();
          return;
        case 'git_diff_result':
          _gitDiffPath = data['path'] as String?;
          _gitDiff = data['diff'] as String? ?? '';
          _gitDiffIsStaged = data['staged'] == true;
          notifyListeners();
          return;
        case 'github_user_result':
          _githubUser = data['user'] is Map<String, dynamic>
              ? data['user'] as Map<String, dynamic>
              : null;
          if (data['error'] != null) _log('[GitHub] ${data['error']}\n');
          notifyListeners();
          return;
        case 'file_tree':
          _fileTree = List<Map<String, dynamic>>.from(data['children']);
          notifyListeners();
          return;
        case 'file_content':
          _fileContents[data['path'] as String] = data['content'] as String;
          notifyListeners();
          return;
        case 'file_saved':
          _fileContents[data['path'] as String] = data['content'] as String;
          _lastSavedFilePath = data['path'] as String;
          _log('Saved ${data['path']}\n');
          return;
        case 'workspace_changed':
          _workspaceChanged = true;
          _log('${data['message']}\n');
          return;
        case 'workspace_opened':
          _projectName = data['projectName'] as String? ?? _projectName;
          _cwd = data['cwd'] as String? ?? _cwd;
          _fileTree = List<Map<String, dynamic>>.from(data['children'] ?? []);
          _fileContents.clear();
          _workspaceOpened = true;
          _log('Opened workspace: $_cwd\n');
          return;
        case 'attachments_result':
          _pendingAttachments = List<Map<String, dynamic>>.from(
            data['attachments'] ?? [],
          );
          notifyListeners();
          return;
        case 'clipboard_paste_result':
          _pendingClipboardPaste = data['result'] is Map<String, dynamic>
              ? data['result'] as Map<String, dynamic>
              : null;
          notifyListeners();
          return;
      }
    } catch (e) {
      _log('$rawData\n');
    }
  }

  /// Public method to inject a message into the AI chat.
  void injectAiMessage({required bool isUser, required String content}) {
    _aiMessages.add({'isUser': isUser, 'content': content});
    notifyListeners();
  }

  void _log(String text) {
    _terminalOutput.add(text);
    notifyListeners();
  }

  @override
  void dispose() {
    _manualDisconnect = true;
    _reconnectTimer?.cancel();
    _channel?.sink.close();
    super.dispose();
  }
}
