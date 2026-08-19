import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Model catalog entry used by LocalModelState
// ─────────────────────────────────────────────────────────────────────────────

class GgufModelSpec {
  final String id;
  final String filename;         // e.g. "qwen3-4b-q4_k_m.gguf"
  final String huggingFaceUrl;   // Direct GGUF download URL
  final int expectedBytes;       // For progress validation

  const GgufModelSpec({
    required this.id,
    required this.filename,
    required this.huggingFaceUrl,
    required this.expectedBytes,
  });
}

/// Catalog of on-device GGUF models Atlas ships with.
const List<GgufModelSpec> kLocalModelCatalog = [
  GgufModelSpec(
    id: 'qwen3-4b',
    filename: 'qwen3-4b-q4_k_m.gguf',
    huggingFaceUrl:
        'https://huggingface.co/Qwen/Qwen3-4B-GGUF/resolve/main/Qwen3-4B-Q4_K_M.gguf',
    expectedBytes: 2_500_000_000,
  ),
  GgufModelSpec(
    id: 'qwen2.5-coder-3b',
    filename: 'qwen2.5-coder-3b-q4_k_m.gguf',
    huggingFaceUrl:
        'https://huggingface.co/Qwen/Qwen2.5-Coder-3B-Instruct-GGUF/resolve/main/qwen2.5-coder-3b-instruct-q4_k_m.gguf',
    expectedBytes: 1_900_000_000,
  ),
  GgufModelSpec(
    id: 'smollm3-3b',
    filename: 'smollm3-3b-q4_k_m.gguf',
    huggingFaceUrl:
        'https://huggingface.co/HuggingFaceTB/SmolLM3-3B-GGUF/resolve/main/smollm3-3b-q4_k_m.gguf',
    expectedBytes: 1_800_000_000,
  ),
];

// ─────────────────────────────────────────────────────────────────────────────
// LocalInferenceService — singleton that owns both Flutter channels
// ─────────────────────────────────────────────────────────────────────────────

/// On non-iOS platforms (debug desktop / Android) the channels don't exist.
/// All methods degrade gracefully with informative errors.
class LocalInferenceService extends ChangeNotifier {
  LocalInferenceService._();

  static final LocalInferenceService instance = LocalInferenceService._();

  // ── Channels ──────────────────────────────────────────────────────────────

  static const _method = MethodChannel('atlas.llama');
  static const _events = EventChannel('atlas.llama.stream');

  // ── State ─────────────────────────────────────────────────────────────────

  bool _modelLoaded = false;
  bool _isGenerating = false;
  String? _loadedModelId;
  final Map<String, double> _downloadProgress = {};

  bool get modelLoaded => _modelLoaded;
  bool get isGenerating => _isGenerating;
  String? get loadedModelId => _loadedModelId;
  double downloadProgress(String modelId) => _downloadProgress[modelId] ?? -1.0;

  // ── Token stream ──────────────────────────────────────────────────────────

  final StreamController<String> _tokenController =
      StreamController<String>.broadcast();

  /// Emits text tokens during active generation.
  Stream<String> get tokenStream => _tokenController.stream;

  // ── Raw event subscription (manages download events too) ──────────────────

  StreamSubscription<dynamic>? _eventSub;

  void _ensureEventSubscription() {
    if (_eventSub != null) return;
    if (!Platform.isIOS) return;

    _eventSub = _events.receiveBroadcastStream().listen((raw) {
      if (raw is String) {
        // Plain token
        _tokenController.add(raw);
      } else if (raw is Map) {
        final map = Map<String, dynamic>.from(raw);
        if (map.containsKey('done')) {
          _isGenerating = false;
          notifyListeners();
          _tokenController.add('\x00done');   // sentinel for consumers
        } else if (map.containsKey('error')) {
          _isGenerating = false;
          notifyListeners();
          _tokenController.addError(Exception(map['error'] as String));
        } else if (map.containsKey('downloadProgress')) {
          final modelId = map['modelId'] as String;
          _downloadProgress[modelId] = (map['downloadProgress'] as num).toDouble();
          notifyListeners();
        } else if (map.containsKey('downloadComplete')) {
          final modelId = map['modelId'] as String;
          _downloadProgress[modelId] = 1.0;
          notifyListeners();
        } else if (map.containsKey('downloadError')) {
          final modelId = map['modelId'] as String;
          _downloadProgress[modelId] = -1.0;
          notifyListeners();
        }
      }
    }, onError: (e) {
      _isGenerating = false;
      notifyListeners();
    });
  }

  // ── Model path helpers ────────────────────────────────────────────────────

  Future<String> _ggufPath(String filename) async {
    final dir = await getApplicationDocumentsDirectory();
    return '${dir.path}/AtlasModels/$filename';
  }

  Future<bool> isModelDownloaded(String modelId) async {
    if (!Platform.isIOS) return false;
    final spec = _specFor(modelId);
    if (spec == null) return false;
    final path = await _ggufPath(spec.filename);
    try {
      return await _method.invokeMethod<bool>('modelExists', {'path': path}) ?? false;
    } catch (_) {
      return false;
    }
  }

  GgufModelSpec? _specFor(String modelId) {
    try {
      return kLocalModelCatalog.firstWhere((s) => s.id == modelId);
    } catch (_) {
      return null;
    }
  }

  // ── Download ──────────────────────────────────────────────────────────────

  Future<void> downloadModel(String modelId) async {
    if (!Platform.isIOS) return;
    final spec = _specFor(modelId);
    if (spec == null) throw Exception('Unknown model: $modelId');

    _ensureEventSubscription();
    _downloadProgress[modelId] = 0.0;
    notifyListeners();

    final destPath = await _ggufPath(spec.filename);
    await _method.invokeMethod<void>('downloadModel', {
      'modelId': modelId,
      'url': spec.huggingFaceUrl,
      'destPath': destPath,
    });
  }

  Future<void> cancelDownload(String modelId) async {
    if (!Platform.isIOS) return;
    await _method.invokeMethod<void>('cancelDownload', {'modelId': modelId});
    _downloadProgress.remove(modelId);
    notifyListeners();
  }

  // ── Load / Unload ─────────────────────────────────────────────────────────

  Future<void> loadModel(String modelId) async {
    if (!Platform.isIOS) {
      throw Exception('Local inference is only supported on iOS/iPadOS.');
    }
    final spec = _specFor(modelId);
    if (spec == null) throw Exception('Unknown model: $modelId');

    _ensureEventSubscription();
    final path = await _ggufPath(spec.filename);
    final result = await _method.invokeMethod<Map>('loadModel', {'path': path});
    if (result?['loaded'] == true) {
      _modelLoaded = true;
      _loadedModelId = modelId;
      notifyListeners();
    }
  }

  Future<void> unloadModel() async {
    if (!Platform.isIOS) return;
    await _method.invokeMethod<void>('unloadModel');
    _modelLoaded = false;
    _loadedModelId = null;
    notifyListeners();
  }

  // ── Generation ────────────────────────────────────────────────────────────

  /// Begin token generation. Tokens are emitted on [tokenStream].
  Future<void> generate({
    required String prompt,
    int maxTokens = 2048,
    double temperature = 0.2,
  }) async {
    if (!Platform.isIOS) {
      throw Exception('Local inference is only supported on iOS/iPadOS.');
    }
    if (!_modelLoaded) throw Exception('No model loaded. Call loadModel() first.');
    if (_isGenerating) throw Exception('Generation already in progress.');

    _isGenerating = true;
    notifyListeners();

    await _method.invokeMethod<void>('generate', {
      'prompt': prompt,
      'maxTokens': maxTokens,
      'temperature': temperature,
    });
  }

  Future<void> cancel() async {
    if (!Platform.isIOS) return;
    await _method.invokeMethod<void>('cancel');
    _isGenerating = false;
    notifyListeners();
  }

  // ── Chat template ─────────────────────────────────────────────────────────

  /// Formats a conversation into a Qwen3 / ChatML prompt string.
  static String buildChatPrompt(List<Map<String, String>> messages) {
    final buf = StringBuffer();
    for (final msg in messages) {
      final role = msg['role'] ?? 'user';
      final content = msg['content'] ?? '';
      buf.write('<|im_start|>$role\n$content<|im_end|>\n');
    }
    buf.write('<|im_start|>assistant\n');
    return buf.toString();
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    _tokenController.close();
    super.dispose();
  }
}
