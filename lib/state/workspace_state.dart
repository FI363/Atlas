import 'package:flutter/material.dart';

import '../services/engine_client.dart';

/// Manages the UI state of the Atlas workspace, including panel visibility,
/// active tabs, and open files. This provides a reactive foundation for iPad layouts.
class WorkspaceState extends ChangeNotifier {
  // Remote Engine
  final EngineClient engine = EngineClient();

  // Panel Visibility State
  bool _isExplorerVisible = true;
  bool _isAiPanelVisible = false;
  bool _isTerminalVisible = false;

  bool _hasRequestedTree = false;

  WorkspaceState() {
    engine.connect('ws://localhost:8080');
    engine.addListener(_onEngineUpdate);
  }

  void _onEngineUpdate() {
    // Request the file tree once we're connected for the first time
    if (engine.isConnected && !_hasRequestedTree) {
      _hasRequestedTree = true;
      engine.requestFileTree();
    }
    notifyListeners();
  }

  @override
  void dispose() {
    engine.removeListener(_onEngineUpdate);
    engine.disconnect();
    super.dispose();
  }

  // Navigation State
  String _activeActivity = 'Explorer';

  // Editor State
  final List<String> _openFiles = [];
  String? _activeFile;

  // Getters
  bool get isExplorerVisible => _isExplorerVisible;
  bool get isAiPanelVisible => _isAiPanelVisible;
  bool get isTerminalVisible => _isTerminalVisible;
  String get activeActivity => _activeActivity;
  
  List<String> get openFiles => List.unmodifiable(_openFiles);
  String? get activeFile => _activeFile;

  // Mutators
  void toggleExplorer() {
    _isExplorerVisible = !_isExplorerVisible;
    if (_isExplorerVisible) _activeActivity = 'Explorer';
    notifyListeners();
  }

  void toggleAiPanel() {
    _isAiPanelVisible = !_isAiPanelVisible;
    notifyListeners();
  }

  void toggleTerminal() {
    _isTerminalVisible = !_isTerminalVisible;
    notifyListeners();
  }

  void setActiveActivity(String activity) {
    if (_activeActivity == activity) {
      if (activity == 'Explorer') {
        toggleExplorer();
        return;
      }
    }
    _activeActivity = activity;
    if (activity == 'Explorer') {
      _isExplorerVisible = true;
    } else {
      _isExplorerVisible = false;
    }
    notifyListeners();
  }

  /// Open a file tab. [filePath] is the relative path from project root (e.g. 'lib/main.dart').
  void openFile(String filePath) {
    if (!_openFiles.contains(filePath)) {
      _openFiles.add(filePath);
    }
    _activeFile = filePath;
    // Request real content from the backend
    engine.requestFileContent(filePath);
    notifyListeners();
  }

  void closeFile(String filename) {
    final index = _openFiles.indexOf(filename);
    if (index == -1) return;
    
    _openFiles.removeAt(index);
    if (_openFiles.isEmpty) {
      _activeFile = null;
    } else if (_activeFile == filename) {
      // Pick the adjacent tab to activate
      _activeFile = _openFiles[index > 0 ? index - 1 : 0];
    }
    notifyListeners();
  }

  void setActiveFile(String filename) {
    if (_openFiles.contains(filename) && _activeFile != filename) {
      _activeFile = filename;
      notifyListeners();
    }
  }
}

