import 'package:flutter/foundation.dart';

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
        return 'Cloud-hosted LLMs (OpenRouter, OpenAI, Claude, Gemini, DeepSeek, Groq)';
      case AiExecutionMode.local:
        return 'Offline on-device inference via llama.cpp + Metal (A16 GPU/NPU)';
      case AiExecutionMode.companion:
        return 'High-parameter agentic coding model hosted on your Windows laptop';
    }
  }
}

enum LocalModelStatus {
  ready,
  downloaded,
  notDownloaded,
  downloading,
  loading,
  error,
}

class LocalModelInfo {
  final String id;
  final String name;
  final String category; // 'Local iPad' | 'Laptop Companion'
  final String runtime; // 'llama.cpp + Metal' | 'Companion Daemon'
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
    this.status = LocalModelStatus.ready,
    this.downloadProgress = 1.0,
    this.errorMessage,
  });
}

/// Manages local on-device models, downloads, context budgets, and runtime execution modes.
class LocalModelState extends ChangeNotifier {
  AiExecutionMode _executionMode = AiExecutionMode.cloud;
  String _selectedLocalModelId = 'qwen3-4b';
  int _contextBudget = 16384; // 8K, 16K, or 32K tokens
  String _streamingState = 'Ready';

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
      status: LocalModelStatus.ready,
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
      status: LocalModelStatus.ready,
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
      status: LocalModelStatus.ready,
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
      status: LocalModelStatus.ready,
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
      status: LocalModelStatus.ready,
    ),
  ];

  AiExecutionMode get executionMode => _executionMode;
  String get selectedLocalModelId => _selectedLocalModelId;
  int get contextBudget => _contextBudget;
  String get streamingState => _streamingState;
  List<LocalModelInfo> get catalog => List.unmodifiable(_catalog);

  LocalModelInfo get activeModel {
    return _catalog.firstWhere(
      (m) => m.id == _selectedLocalModelId,
      orElse: () => _catalog.first,
    );
  }

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

  void startModelDownload(String modelId) {
    final model = _catalog.firstWhere((m) => m.id == modelId, orElse: () => _catalog.first);
    model.status = LocalModelStatus.downloading;
    model.downloadProgress = 0.05;
    notifyListeners();

    // Simulate steady progress feedback
    Future.delayed(const Duration(milliseconds: 400), () {
      model.downloadProgress = 0.40;
      notifyListeners();
      Future.delayed(const Duration(milliseconds: 600), () {
        model.downloadProgress = 0.85;
        notifyListeners();
        Future.delayed(const Duration(milliseconds: 500), () {
          model.downloadProgress = 1.0;
          model.status = LocalModelStatus.ready;
          notifyListeners();
        });
      });
    });
  }

  void unloadModel(String modelId) {
    final model = _catalog.firstWhere((m) => m.id == modelId, orElse: () => _catalog.first);
    model.status = LocalModelStatus.downloaded;
    notifyListeners();
  }

  void loadModel(String modelId) {
    final model = _catalog.firstWhere((m) => m.id == modelId, orElse: () => _catalog.first);
    model.status = LocalModelStatus.loading;
    _streamingState = 'Loading model into memory...';
    notifyListeners();

    Future.delayed(const Duration(milliseconds: 600), () {
      model.status = LocalModelStatus.ready;
      _streamingState = 'Ready';
      notifyListeners();
    });
  }
}
