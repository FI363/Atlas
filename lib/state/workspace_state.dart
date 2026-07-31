import 'package:flutter/material.dart';

import '../config/atlas_config.dart';
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
    engine.connect(
      url: AtlasConfig.engineUrl,
      token: AtlasConfig.engineToken,
    );
    engine.addListener(_onEngineUpdate);
  }

  void _onEngineUpdate() {
    // Request the file tree once we're connected for the first time
    if (engine.isConnected && !_hasRequestedTree) {
      _hasRequestedTree = true;
      engine.requestFileTree();
    }
    final savedFilePath = engine.takeLastSavedFilePath();
    if (savedFilePath != null) _drafts.remove(savedFilePath);
    if (engine.takeWorkspaceChanged()) engine.requestFileTree();
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
  final Map<String, String> _drafts = {};
  String? _activeFile;

  // Getters
  bool get isExplorerVisible => _isExplorerVisible;
  bool get isAiPanelVisible => _isAiPanelVisible;
  bool get isTerminalVisible => _isTerminalVisible;
  String get activeActivity => _activeActivity;
  
  List<String> get openFiles => List.unmodifiable(_openFiles);
  String? get activeFile => _activeFile;
  String? contentForFile(String filePath) =>
      _drafts[filePath] ?? engine.getFileContent(filePath);
  bool hasUnsavedChanges(String filePath) => _drafts.containsKey(filePath);

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
    _drafts.remove(filename);
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

  /// Sends an updated file to the authenticated companion engine.
  void saveFile(String filePath, String content) {
    engine.saveFile(filePath, content);
  }

  /// Keeps a local edit while the file is open or waiting for a save response.
  void updateDraft(String filePath, String content) {
    _drafts[filePath] = content;
    notifyListeners();
  }

  void discardDraft(String filePath) {
    _drafts.remove(filePath);
    notifyListeners();
  }

  void createFile(String filePath) => engine.createFile(filePath);

  void createDirectory(String directoryPath) => engine.createDirectory(directoryPath);
}
