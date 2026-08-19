import 'dart:io';
import 'package:flutter/foundation.dart';
import '../services/local_inference_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Enums
// ─────────────────────────────────────────────────────────────────────────────

enum AiExecutionMode {
  cloud,
  local,
  companion,
}

extension AiExecutionModeExt on AiExecutionMode {
  String get label {
    switch (this) {
      case AiExecutionMode.cloud:
        return 'Cloud AI';
      case AiExecutionMode.local:
        return 'Local iPad AI';
      case AiExecutionMode.companion:
        return 'Laptop Companion AI';
    }
  }

  String get shortLabel {
    switch (this) {
      case AiExecutionMode.cloud:
        return 'Cloud';
      case AiExecutionMode.local:
        return 'Local AI';
      case AiExecutionMode.companion:
        return 'Laptop';
    }
  }

  String get description {
    switch (this) {
      case AiExecutionMode.cloud:
        return 'Cloud-hosted LLMs via OpenRouter and Custom Endpoints';
      case AiExecutionMode.local:
        return 'Offline on-device inference via llama.cpp + Metal (A16 GPU/NPU)';
      case AiExecutionMode.companion:
        return 'High-parameter agentic coding model hosted on your Windows laptop';
    }
  }
}

enum LocalModelStatus {
  ready,       // Model loaded in memory and ready for inference
  downloaded,  // GGUF present on disk but not loaded
  notDownloaded,
  downloading,
  loading,
  error,
}

// ─────────────────────────────────────────────────────────────────────────────
// Model info record
// ─────────────────────────────────────────────────────────────────────────────

class LocalModelInfo {
  final String id;
  final String name;
  final String category; // 'Local iPad' | 'Laptop Companion'
  final String runtime;  // 'llama.cpp + Metal' | 'Companion Daemon'
  final String quantization;
  final String downloadSize;
  final String requiredMemory;
  final String contextBudget;
  final List<String> capabilities;
  LocalModelStatus status;
  double downloadProgress;
  String? errorMessage;

  LocalModelInfo({
    required this.id,
    required this.name,
    required this.category,
    required this.runtime,
    required this.quantization,
    required this.downloadSize,
    required this.requiredMemory,
    required this.contextBudget,
    required this.capabilities,
    this.status = LocalModelStatus.notDownloaded,
    this.downloadProgress = 0.0,
    this.errorMessage,
  });

  /// Whether this model can be run locally on-device (vs. laptop companion).
  bool get isLocalModel => runtime.contains('llama.cpp');
}

// ─────────────────────────────────────────────────────────────────────────────
// LocalModelState
// ─────────────────────────────────────────────────────────────────────────────

/// Manages local on-device models, downloads, context budgets, and runtime
/// execution modes. Delegates actual inference to [LocalInferenceService].
class LocalModelState extends ChangeNotifier {
  AiExecutionMode _executionMode = AiExecutionMode.cloud;
  String _selectedLocalModelId = 'qwen3-4b';
  int _contextBudget = 16384;
  String _streamingState = 'Ready';
  String? _lastError;

  final LocalInferenceService _inference = LocalInferenceService.instance;

  final List<LocalModelInfo> _catalog = [
    LocalModelInfo(
      id: 'qwen3-4b',
      name: 'Qwen3 4B Instruct',
      category: 'Local iPad (Primary)',
      runtime: 'llama.cpp + Metal',
      quantization: 'Q4_K_M',
      downloadSize: '2.5 GB GGUF',
      requiredMemory: '~3.2 GB RAM (A16 Metal)',
      contextBudget: '16K tokens (8K–32K budget)',
      capabilities: ['Code Generation', 'Agent Tools', 'Patch Generation', 'Multi-File', 'Offline'],
    ),
    LocalModelInfo(
      id: 'qwen2.5-coder-3b',
      name: 'Qwen2.5 Coder 3B Instruct',
      category: 'Local iPad (Lightweight)',
      runtime: 'llama.cpp + Metal',
      quantization: 'Q4_K_M',
      downloadSize: '1.9 GB GGUF',
      requiredMemory: '~2.4 GB RAM',
      contextBudget: '16K tokens',
      capabilities: ['Fast Autocomplete', 'Code Analysis', 'Bug Fixing', 'Offline'],
    ),
    LocalModelInfo(
      id: 'smollm3-3b',
      name: 'SmolLM3 3B',
      category: 'Local iPad (Ultra-Compact)',
      runtime: 'llama.cpp + Metal',
      quantization: 'Q4_K_M',
      downloadSize: '1.8 GB GGUF',
      requiredMemory: '~2.1 GB RAM',
      contextBudget: '8K tokens',
      capabilities: ['Instruction Following', 'Explanation', 'Basic Tools', 'Offline'],
    ),
    LocalModelInfo(
      id: 'qwen3-coder-next',
      name: 'Qwen3-Coder-Next (80B MoE)',
      category: 'Laptop Companion (Server)',
      runtime: 'Atlas Laptop Companion Daemon',
      quantization: 'FP8 / Q4_K_M',
      downloadSize: '42 GB Server Model',
      requiredMemory: '16+ GB Laptop RAM / GPU',
      contextBudget: '64K–128K context window',
      capabilities: ['Full Codebase Architecture', 'Deep Refactoring', 'Automated Testing', 'Git Flow'],
      status: LocalModelStatus.downloaded,
      downloadProgress: 1.0,
    ),
    LocalModelInfo(
      id: 'devstral-small-2',
      name: 'Devstral Small 2',
      category: 'Laptop Companion (Server)',
      runtime: 'Atlas Laptop Companion Daemon',
      quantization: 'Q4_K_M',
      downloadSize: '14 GB Server Model',
      requiredMemory: '8+ GB Laptop RAM',
      contextBudget: '32K context window',
      capabilities: ['Software Engineering Agent', 'Multi-File Edits', 'Test Generation'],
      status: LocalModelStatus.downloaded,
      downloadProgress: 1.0,
    ),
  ];

  // ── Getters ───────────────────────────────────────────────────────────────

  AiExecutionMode get executionMode => _executionMode;
  String get selectedLocalModelId => _selectedLocalModelId;
  int get contextBudget => _contextBudget;
  String get streamingState => _streamingState;
  String? get lastError => _lastError;
  List<LocalModelInfo> get catalog => List.unmodifiable(_catalog);
  bool get isIOS => Platform.isIOS;

  LocalModelInfo get activeModel {
    return _catalog.firstWhere(
      (m) => m.id == _selectedLocalModelId,
      orElse: () => _catalog.first,
    );
  }

  /// Token stream from the active local model.
  Stream<String> get tokenStream => _inference.tokenStream;

  bool get isLocalModelGenerating => _inference.isGenerating;

  // ── Init: check which models exist on disk ────────────────────────────────

  Future<void> refreshDownloadStatus() async {
    if (!Platform.isIOS) {
      // On non-iOS platforms mark local models as not-available
      for (final m in _catalog) {
        if (m.isLocalModel) m.status = LocalModelStatus.notDownloaded;
      }
      notifyListeners();
      return;
    }
    for (final m in _catalog) {
      if (!m.isLocalModel) continue;
      final exists = await _inference.isModelDownloaded(m.id);
      m.status = exists ? LocalModelStatus.downloaded : LocalModelStatus.notDownloaded;
      m.downloadProgress = exists ? 1.0 : 0.0;
    }
    notifyListeners();
  }

  // ── Execution mode ────────────────────────────────────────────────────────

  void setExecutionMode(AiExecutionMode mode) {
    _executionMode = mode;
    notifyListeners();
  }

  void selectModel(String modelId) {
    if (_catalog.any((m) => m.id == modelId)) {
      _selectedLocalModelId = modelId;
      notifyListeners();
    }
  }

  void setContextBudget(int budgetTokens) {
    _contextBudget = budgetTokens;
    notifyListeners();
  }

  void updateStreamingState(String state) {
    _streamingState = state;
    notifyListeners();
  }

  // ── Download ──────────────────────────────────────────────────────────────

  Future<void> startModelDownload(String modelId) async {
    final model = _modelById(modelId);
    if (model == null) return;

    model.status = LocalModelStatus.downloading;
    model.downloadProgress = 0.0;
    model.errorMessage = null;
    notifyListeners();

    // Forward real download progress from the service
    _inference.addListener(_onInferenceUpdate);

    try {
      await _inference.downloadModel(modelId);
      // onInferenceUpdate will update progress; completion sets status.
    } catch (e) {
      model.status = LocalModelStatus.error;
      model.errorMessage = e.toString();
      _lastError = e.toString();
      _inference.removeListener(_onInferenceUpdate);
      notifyListeners();
    }
  }

  void _onInferenceUpdate() {
    for (final m in _catalog) {
      if (!m.isLocalModel) continue;
      final progress = _inference.downloadProgress(m.id);
      if (progress >= 0) {
        m.downloadProgress = progress;
        if (progress >= 1.0 && m.status == LocalModelStatus.downloading) {
          m.status = LocalModelStatus.downloaded;
          _inference.removeListener(_onInferenceUpdate);
        }
      }
    }
    notifyListeners();
  }

  Future<void> cancelDownload(String modelId) async {
    final model = _modelById(modelId);
    if (model == null) return;
    await _inference.cancelDownload(modelId);
    model.status = LocalModelStatus.notDownloaded;
    model.downloadProgress = 0.0;
    notifyListeners();
  }

  // ── Load / Unload ─────────────────────────────────────────────────────────

  Future<void> loadModel(String modelId) async {
    final model = _modelById(modelId);
    if (model == null) return;

    model.status = LocalModelStatus.loading;
    _streamingState = 'Loading model into memory...';
    _lastError = null;
    notifyListeners();

    try {
      await _inference.loadModel(modelId);
      model.status = LocalModelStatus.ready;
      _streamingState = 'Ready';
      notifyListeners();
    } catch (e) {
      model.status = LocalModelStatus.error;
      model.errorMessage = e.toString();
      _lastError = e.toString();
      _streamingState = 'Load failed';
      notifyListeners();
    }
  }

  Future<void> unloadModel(String modelId) async {
    final model = _modelById(modelId);
    if (model == null) return;
    await _inference.unloadModel();
    model.status = LocalModelStatus.downloaded;
    _streamingState = 'Ready';
    notifyListeners();
  }

  // ── Inference ─────────────────────────────────────────────────────────────

  /// Run a prompt through the locally loaded model.
  /// Tokens stream via [tokenStream]; subscribe before calling this.
  Future<void> runLocalPrompt(
    String prompt, {
    List<Map<String, String>> chatHistory = const [],
    int? maxTokens,
    double? temperature,
  }) async {
    _streamingState = 'Generating...';
    _lastError = null;
    notifyListeners();

    try {
      final messages = <Map<String, String>>[
        ...chatHistory,
        {'role': 'user', 'content': prompt},
      ];
      final formattedPrompt = LocalInferenceService.buildChatPrompt(messages);

      await _inference.generate(
        prompt: formattedPrompt,
        maxTokens: maxTokens ?? _contextBudget,
        temperature: temperature ?? 0.2,
      );

      _streamingState = 'Done';
      notifyListeners();
    } catch (e) {
      _lastError = e.toString();
      _streamingState = 'Error: $e';
      notifyListeners();
      rethrow;
    }
  }

  Future<void> cancelGeneration() async {
    await _inference.cancel();
    _streamingState = 'Cancelled';
    notifyListeners();
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  LocalModelInfo? _modelById(String id) {
    try {
      return _catalog.firstWhere((m) => m.id == id);
    } catch (_) {
      return null;
    }
  }
}
