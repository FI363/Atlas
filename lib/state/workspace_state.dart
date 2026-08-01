import 'package:flutter/material.dart';

import '../config/atlas_config.dart';
import '../services/engine_client.dart';
import 'atlas_settings.dart';

/// Reactive workspace state: panel visibility, open tabs, drafts, resizable panel dimensions,
/// command palette state, and the engine connection.
class WorkspaceState extends ChangeNotifier {
  final EngineClient engine = EngineClient();

  /// Live settings object — mutate fields then call [applySettings] to notify.
  final AtlasSettings settings = AtlasSettings();

  // Panel visibility
  bool _explorerVisible = true;
  bool _aiPanelVisible = false;
  bool _terminalVisible = false;
  bool _commandPaletteVisible = false;
  bool _settingsPanelVisible = false;

  // Panel dimensions (dynamic resizable layout)
  double _explorerWidth = 260.0;
  double _aiPanelWidth = 340.0;
  double _terminalHeight = 220.0;

  // Navigation
  String _activeActivity = 'Explorer';

  // Editor
  final List<String> _openFiles = [];
  final Map<String, String> _drafts = {};
  String? _activeFile;

  bool _hasRequestedTree = false;

  WorkspaceState() {
    engine.connect(
      url: AtlasConfig.engineUrl,
      token: AtlasConfig.engineToken,
    );
    engine.addListener(_onEngineUpdate);
  }

  @override
  void dispose() {
    engine.removeListener(_onEngineUpdate);
    engine.disconnect();
    super.dispose();
  }

  // ── Getters ─────────────────────────────────────────────────────────────

  String get defaultRunCommand => settings.runCommand;

  bool get isExplorerVisible => _explorerVisible;
  bool get isAiPanelVisible => _aiPanelVisible;
  bool get isTerminalVisible => _terminalVisible;
  bool get isCommandPaletteVisible => _commandPaletteVisible;
  bool get isSettingsPanelVisible => _settingsPanelVisible;

  double get explorerWidth => _explorerWidth;
  double get aiPanelWidth => _aiPanelWidth;
  double get terminalHeight => _terminalHeight;

  String get activeActivity => _activeActivity;
  String get projectName => engine.projectName;

  List<String> get openFiles => List.unmodifiable(_openFiles);
  String? get activeFile => _activeFile;

  String? contentForFile(String filePath) =>
      _drafts[filePath] ?? engine.getFileContent(filePath);

  bool hasUnsavedChanges(String filePath) => _drafts.containsKey(filePath);
  bool get hasAnyUnsavedChanges => _drafts.isNotEmpty;

  // ── Panel Resizing ──────────────────────────────────────────────────────

  void setExplorerWidth(double width) {
    _explorerWidth = width.clamp(160.0, 500.0);
    notifyListeners();
  }

  void setAiPanelWidth(double width) {
    _aiPanelWidth = width.clamp(200.0, 550.0);
    notifyListeners();
  }

  void setTerminalHeight(double height) {
    _terminalHeight = height.clamp(100.0, 500.0);
    notifyListeners();
  }

  // ── Panel Toggles ──────────────────────────────────────────────────────

  void toggleExplorer() {
    _explorerVisible = !_explorerVisible;
    if (_explorerVisible) _activeActivity = 'Explorer';
    notifyListeners();
  }

  void toggleAiPanel() {
    _aiPanelVisible = !_aiPanelVisible;
    notifyListeners();
  }

  void toggleTerminal() {
    _terminalVisible = !_terminalVisible;
    notifyListeners();
  }

  void toggleCommandPalette() {
    _commandPaletteVisible = !_commandPaletteVisible;
    notifyListeners();
  }

  void openSettings() {
    _settingsPanelVisible = true;
    notifyListeners();
  }

  void closeSettings() {
    _settingsPanelVisible = false;
    // Pop back to Explorer after closing settings
    if (_activeActivity == 'Settings') {
      _activeActivity = 'Explorer';
      _explorerVisible = true;
    }
    notifyListeners();
  }

  /// Call after mutating fields on [settings] to propagate changes.
  void applySettings() {
    notifyListeners();
  }

  void setActiveActivity(String activity) {
    if (activity == 'Settings') {
      _activeActivity = 'Settings';
      _explorerVisible = false;
      _settingsPanelVisible = true;
      notifyListeners();
      return;
    }
    if (_activeActivity == activity && activity == 'Explorer') {
      toggleExplorer();
      return;
    }
    _settingsPanelVisible = false;
    _activeActivity = activity;
    _explorerVisible = activity == 'Explorer';
    notifyListeners();
  }

  // ── Execution & File operations ────────────────────────────────────────

  /// Opens the terminal if closed and runs the target command.
  void runProject([String? command]) {
    if (!_terminalVisible) {
      _terminalVisible = true;
    }
    engine.runCommand(command ?? defaultRunCommand);
    notifyListeners();
  }

  void openFile(String filePath) {
    if (!_openFiles.contains(filePath)) _openFiles.add(filePath);
    _activeFile = filePath;
    engine.requestFileContent(filePath);
    notifyListeners();
  }

  void closeFile(String filePath) {
    final index = _openFiles.indexOf(filePath);
    if (index == -1) return;

    _openFiles.removeAt(index);
    _drafts.remove(filePath);

    if (_openFiles.isEmpty) {
      _activeFile = null;
    } else if (_activeFile == filePath) {
      _activeFile = _openFiles[index > 0 ? index - 1 : 0];
    }
    notifyListeners();
  }

  void setActiveFile(String filePath) {
    if (_openFiles.contains(filePath) && _activeFile != filePath) {
      _activeFile = filePath;
      notifyListeners();
    }
  }

  void saveFile(String filePath, String content) =>
      engine.saveFile(filePath, content);

  void saveCurrentFile() {
    if (_activeFile != null) {
      final content = contentForFile(_activeFile!);
      if (content != null) {
        saveFile(_activeFile!, content);
      }
    }
  }

  void saveAllFiles() {
    final draftEntries = Map<String, String>.from(_drafts);
    for (final entry in draftEntries.entries) {
      saveFile(entry.key, entry.value);
    }
  }

  void updateDraft(String filePath, String content) {
    _drafts[filePath] = content;
    notifyListeners();
  }

  void discardDraft(String filePath) {
    _drafts.remove(filePath);
    notifyListeners();
  }

  void createFile(String path) => engine.createFile(path);
  void createDirectory(String path) => engine.createDirectory(path);

  // ── Engine listener ────────────────────────────────────────────────────

  void _onEngineUpdate() {
    if (engine.isConnected && !_hasRequestedTree) {
      _hasRequestedTree = true;
      engine.requestFileTree();
    }

    final saved = engine.takeLastSavedFilePath();
    if (saved != null) _drafts.remove(saved);

    if (engine.takeWorkspaceChanged()) engine.requestFileTree();

    notifyListeners();
  }
}
