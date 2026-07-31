import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Service for connecting to the remote Atlas Backend Engine via WebSockets
class EngineClient extends ChangeNotifier {
  WebSocketChannel? _channel;
  bool _isConnected = false;
  
  // Terminal output stream
  final List<String> _terminalOutput = [];

  // File system data
  List<Map<String, dynamic>> _fileTree = [];
  final Map<String, String> _fileContents = {};
  String? _lastSavedFilePath;
  bool _workspaceChanged = false;

  bool get isConnected => _isConnected;
  List<String> get terminalOutput => List.unmodifiable(_terminalOutput);
  List<Map<String, dynamic>> get fileTree => _fileTree;
  
  /// Get cached file content (or null if not loaded yet)
  String? getFileContent(String path) => _fileContents[path];

  /// Returns and clears the most recently confirmed save path.
  String? takeLastSavedFilePath() {
    final path = _lastSavedFilePath;
    _lastSavedFilePath = null;
    return path;
  }

  /// Returns whether the engine confirmed a file-system change since last read.
  bool takeWorkspaceChanged() {
    final changed = _workspaceChanged;
    _workspaceChanged = false;
    return changed;
  }

  /// Connect to the remote engine and authenticate before sending requests.
  Future<void> connect({required String url, required String token}) async {
    if (token.isEmpty) {
      _appendTerminalOutput(
        'Atlas engine token is missing. Rebuild with --dart-define=ATLAS_ENGINE_TOKEN=...\n',
      );
      return;
    }

    try {
      _channel = WebSocketChannel.connect(Uri.parse(url));

      _channel!.stream.listen(
        (message) {
          _handleIncomingMessage(message);
        },
        onDone: () {
          _isConnected = false;
          _appendTerminalOutput('Disconnected from remote engine.\n');
          notifyListeners();
        },
        onError: (error) {
          _isConnected = false;
          _appendTerminalOutput('Connection error: $error\n');
          notifyListeners();
        },
      );

      await _channel!.ready;
      _isConnected = true;
      _channel!.sink.add(jsonEncode({'type': 'auth', 'token': token}));
      notifyListeners();
    } catch (e) {
      _isConnected = false;
      _appendTerminalOutput('Failed to connect to Atlas engine: $e\n');
      notifyListeners();
    }
  }

  /// Close the WebSocket connection
  void disconnect() {
    _channel?.sink.close();
    _isConnected = false;
    notifyListeners();
  }

  /// Execute a shell command on the remote engine
  void runCommand(String command) {
    if (!_isConnected) {
      _appendTerminalOutput('Cannot run command: Not connected to engine.\n');
      return;
    }
    
    _appendTerminalOutput('\$ $command\n');
    _channel!.sink.add(jsonEncode({
      'type': 'cmd',
      'command': command,
    }));
  }

  /// Request the project file tree from the backend
  void requestFileTree() {
    if (!_isConnected) return;
    _channel!.sink.add(jsonEncode({'type': 'list_dir'}));
  }

  /// Request a file's contents from the backend
  void requestFileContent(String filePath) {
    if (!_isConnected) return;
    _channel!.sink.add(jsonEncode({
      'type': 'read_file',
      'path': filePath,
    }));
  }

  /// Persist [content] to an existing file in the opened project.
  void saveFile(String filePath, String content) {
    if (!_isConnected) {
      _appendTerminalOutput('Cannot save file: Not connected to engine.\n');
      return;
    }
    _channel!.sink.add(jsonEncode({
      'type': 'write_file',
      'path': filePath,
      'content': content,
    }));
  }

  void createFile(String filePath) => _createWorkspaceEntry('create_file', filePath);

  void createDirectory(String directoryPath) =>
      _createWorkspaceEntry('create_directory', directoryPath);

  void _createWorkspaceEntry(String type, String path) {
    if (!_isConnected) {
      _appendTerminalOutput('Cannot create workspace entry: Not connected to engine.\n');
      return;
    }
    _channel!.sink.add(jsonEncode({'type': type, 'path': path}));
  }

  void _handleIncomingMessage(String rawData) {
    try {
      final data = jsonDecode(rawData);
      final type = data['type'];
      
      if (type == 'system') {
        _appendTerminalOutput('[SYSTEM] ${data['message']}\n');
      } else if (type == 'output') {
        _appendTerminalOutput(data['content']);
      } else if (type == 'error') {
        _appendTerminalOutput('[ERROR] ${data['content']}');
      } else if (type == 'exit') {
        _appendTerminalOutput('[Process exited with code ${data['code']}]\n');
      } else if (type == 'file_tree') {
        _fileTree = List<Map<String, dynamic>>.from(data['children']);
        notifyListeners();
        return; // Already notified
      } else if (type == 'file_content') {
        _fileContents[data['path']] = data['content'];
        notifyListeners();
        return; // Already notified
      } else if (type == 'file_saved') {
        _fileContents[data['path']] = data['content'];
        _lastSavedFilePath = data['path'];
        _appendTerminalOutput('Saved ${data['path']}\n');
        return;
      } else if (type == 'workspace_changed') {
        _workspaceChanged = true;
        _appendTerminalOutput('${data['message']}\n');
        return;
      }
    } catch (e) {
      // Raw string fallback
      _appendTerminalOutput('$rawData\n');
    }
  }

  void _appendTerminalOutput(String text) {
    _terminalOutput.add(text);
    notifyListeners();
  }
}
