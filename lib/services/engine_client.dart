import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Service for connecting to the remote Atlas Backend Engine via WebSockets
class EngineClient extends ChangeNotifier {
  WebSocketChannel? _channel;
  bool _isConnected = false;

  final List<String> _terminalOutput = [];
  List<Map<String, dynamic>> _fileTree = [];
  final Map<String, String> _fileContents = {};

  bool get isConnected => _isConnected;
  List<String> get terminalOutput => List.unmodifiable(_terminalOutput);
  List<Map<String, dynamic>> get fileTree => _fileTree;

  /// Get cached file content (or null if not loaded yet)
  String? getFileContent(String path) => _fileContents[path];

  /// Connect to the remote engine running on the laptop
  void connect(String wsUrl) {
    try {
      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));

      _channel!.stream.listen(
        (message) {
          _isConnected = true;
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

      notifyListeners();
    } catch (e) {
      _appendTerminalOutput('Failed to connect: $e\n');
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
    _sendMessage({'type': 'cmd', 'command': command});
  }

  /// Request the project file tree from the backend
  void requestFileTree() {
    if (!_isConnected) return;
    _sendMessage({'type': 'list_dir'});
  }

  /// Request a file's contents from the backend
  void requestFileContent(String filePath) {
    if (!_isConnected) return;
    _sendMessage({'type': 'read_file', 'path': filePath});
  }

  /// Save a file's contents back to the backend
  void saveFile(String filePath, String content) {
    if (!_isConnected) {
      _appendTerminalOutput('Cannot save file: Not connected to engine.\n');
      return;
    }

    _sendMessage({'type': 'write_file', 'path': filePath, 'content': content});
  }

  void _sendMessage(Map<String, Object?> payload) {
    _channel?.sink.add(jsonEncode(payload));
  }

  void _handleIncomingMessage(String rawData) {
    try {
      final data = jsonDecode(rawData) as Map<String, dynamic>;
      final type = data['type'];

      if (type == 'system') {
        _appendTerminalOutput('[SYSTEM] ${data['message']}\n');
      } else if (type == 'output') {
        _appendTerminalOutput(data['content'] as String);
      } else if (type == 'error') {
        _appendTerminalOutput('[ERROR] ${data['content']}');
      } else if (type == 'exit') {
        _appendTerminalOutput('[Process exited with code ${data['code']}]\n');
      } else if (type == 'file_tree') {
        _fileTree = List<Map<String, dynamic>>.from(
          data['children'] as List<dynamic>,
        );
        notifyListeners();
        return;
      } else if (type == 'file_content') {
        _fileContents[data['path'] as String] = data['content'] as String;
        notifyListeners();
        return;
      }
    } catch (e) {
      _appendTerminalOutput('$rawData\n');
    }
  }

  void _appendTerminalOutput(String text) {
    _terminalOutput.add(text);
    notifyListeners();
  }
}
