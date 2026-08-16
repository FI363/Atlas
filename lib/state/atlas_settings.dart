/// All persistent Atlas user settings. Passed to WorkspaceState and widgets
/// so every part of the app can react to changes without rebuilding the whole tree.
class AtlasSettings {
  // ── Editor ────────────────────────────────────────────────────────────────
  double fontSize = 13.5;
  int tabSize = 2;
  bool wordWrap = false;
  bool showLineNumbers = true;
  bool autoSave = false;
  String fontFamily = 'Consolas';

  // ── Terminal ──────────────────────────────────────────────────────────────
  double terminalFontSize = 13.0;
  int terminalHistoryLimit = 500;
  String defaultShell = 'powershell';

  // ── Run / Build ───────────────────────────────────────────────────────────
  String runCommand = 'flutter run -d chrome';

  // ── AI Agent ──────────────────────────────────────────────────────────────
  AiProvider aiProvider = AiProvider.openRouter;
  bool useAgentMode = true;
  String agentPermissionPolicy = 'approve_write'; // 'approve_write' | 'approve_all' | 'auto_all'
  int agentMaxIterations = 25;
  String openRouterEndpoint = 'https://openrouter.ai/api/v1';
  String openRouterApiKey = '';
  String openRouterModel = 'google/gemini-2.5-flash';
  String ollamaEndpoint = 'http://localhost:11434';
  String ollamaModel = 'qwen3:4b';
  String openAiEndpoint = 'https://api.openai.com/v1';
  String openAiApiKey = '';
  String openAiModel = 'gpt-4o';
  bool allowFullAiAccess = true; // Full AI access flag
  String customAgentEndpoint = '';
  int aiMaxTokens = 4096;
  double aiTemperature = 0.2;
  String aiSystemPrompt =
      'You are Atlas, an expert agentic AI software engineer embedded in Atlas IDE. '
      'Your job is to analyze, write, refactor, and debug code directly for the developer. '
      'When providing code changes or new implementations:\n'
      '1. Always output complete, ready-to-run code snippets inside markdown code blocks (e.g. ```dart:lib/main.dart or ```javascript).\n'
      '2. Specify the relative target file path after a colon in the code block header if applicable (e.g. ```dart:lib/main.dart).\n'
      '3. For terminal commands, use ```bash or ```powershell.\n'
      '4. Keep explanations clear, professional, and concise.';

  // ── Engine ────────────────────────────────────────────────────────────────
  String engineToken = 'dev-token';
  String engineUrl = 'ws://localhost:8080';

  // ── GitHub Integration ───────────────────────────────────────────────────
  String githubToken = '';
  String githubUsername = 'FI363';

  // ── Theme / UI ────────────────────────────────────────────────────────────
  bool minimap = false;
  bool breadcrumbs = true;
  bool smoothScrolling = true;

  AtlasSettings();

  void applyMap(Map<String, dynamic> values) {
    fontSize = (values['fontSize'] as num?)?.toDouble() ?? fontSize;
    tabSize = (values['tabSize'] as num?)?.toInt() ?? tabSize;
    if (values['wordWrap'] is bool) wordWrap = values['wordWrap'] as bool;
    if (values['showLineNumbers'] is bool) showLineNumbers = values['showLineNumbers'] as bool;
    if (values['autoSave'] is bool) autoSave = values['autoSave'] as bool;
    if (values['fontFamily'] is String) fontFamily = values['fontFamily'] as String;
    terminalFontSize = (values['terminalFontSize'] as num?)?.toDouble() ?? terminalFontSize;
    terminalHistoryLimit = (values['terminalHistoryLimit'] as num?)?.toInt() ?? terminalHistoryLimit;
    if (values['defaultShell'] is String) defaultShell = values['defaultShell'] as String;
    if (values['runCommand'] is String) runCommand = values['runCommand'] as String;
    
    if (values['aiProvider'] is String) {
      final provider = values['aiProvider'] as String;
      aiProvider = AiProvider.values.firstWhere((item) => item.name == provider, orElse: () => aiProvider);
    }
    if (values['useAgentMode'] is bool) useAgentMode = values['useAgentMode'] as bool;
    if (values['agentPermissionPolicy'] is String) agentPermissionPolicy = values['agentPermissionPolicy'] as String;
    agentMaxIterations = (values['agentMaxIterations'] as num?)?.toInt() ?? agentMaxIterations;
    if (values['openRouterEndpoint'] is String) openRouterEndpoint = values['openRouterEndpoint'] as String;
    if (values['openRouterApiKey'] is String) openRouterApiKey = values['openRouterApiKey'] as String;
    if (values['openRouterModel'] is String) openRouterModel = values['openRouterModel'] as String;
    if (values['ollamaEndpoint'] is String) ollamaEndpoint = values['ollamaEndpoint'] as String;
    if (values['ollamaModel'] is String) ollamaModel = values['ollamaModel'] as String;
    if (values['openAiEndpoint'] is String) openAiEndpoint = values['openAiEndpoint'] as String;
    if (values['openAiApiKey'] is String) openAiApiKey = values['openAiApiKey'] as String;
    if (values['openAiModel'] is String) openAiModel = values['openAiModel'] as String;
    if (values['customAgentEndpoint'] is String) customAgentEndpoint = values['customAgentEndpoint'] as String;
    aiMaxTokens = (values['aiMaxTokens'] as num?)?.toInt() ?? aiMaxTokens;
    aiTemperature = (values['aiTemperature'] as num?)?.toDouble() ?? aiTemperature;
    if (values['aiSystemPrompt'] is String) aiSystemPrompt = values['aiSystemPrompt'] as String;
    if (values['allowFullAiAccess'] is bool) allowFullAiAccess = values['allowFullAiAccess'] as bool;
    if (values['githubToken'] is String) githubToken = values['githubToken'] as String;
    if (values['githubUsername'] is String) githubUsername = values['githubUsername'] as String;
    if (values['engineToken'] is String) engineToken = values['engineToken'] as String;
    if (values['engineUrl'] is String) engineUrl = values['engineUrl'] as String;
    if (values['minimap'] is bool) minimap = values['minimap'] as bool;
    if (values['breadcrumbs'] is bool) breadcrumbs = values['breadcrumbs'] as bool;
    if (values['smoothScrolling'] is bool) smoothScrolling = values['smoothScrolling'] as bool;
  }

  Map<String, dynamic> toMap() {
    return {
      'fontSize': fontSize,
      'tabSize': tabSize,
      'wordWrap': wordWrap,
      'showLineNumbers': showLineNumbers,
      'autoSave': autoSave,
      'fontFamily': fontFamily,
      'terminalFontSize': terminalFontSize,
      'terminalHistoryLimit': terminalHistoryLimit,
      'defaultShell': defaultShell,
      'runCommand': runCommand,
      'aiProvider': aiProvider.name,
      'useAgentMode': useAgentMode,
      'agentPermissionPolicy': agentPermissionPolicy,
      'agentMaxIterations': agentMaxIterations,
      'openRouterEndpoint': openRouterEndpoint,
      'openRouterApiKey': openRouterApiKey,
      'openRouterModel': openRouterModel,
      'ollamaEndpoint': ollamaEndpoint,
      'ollamaModel': ollamaModel,
      'openAiEndpoint': openAiEndpoint,
      'openAiApiKey': openAiApiKey,
      'openAiModel': openAiModel,
      'customAgentEndpoint': customAgentEndpoint,
      'aiMaxTokens': aiMaxTokens,
      'aiTemperature': aiTemperature,
      'aiSystemPrompt': aiSystemPrompt,
      'githubToken': githubToken,
      'githubUsername': githubUsername,
      'engineToken': engineToken,
      'engineUrl': engineUrl,
      'minimap': minimap,
      'breadcrumbs': breadcrumbs,
      'smoothScrolling': smoothScrolling,
      'allowFullAiAccess': allowFullAiAccess,
    };
  }
}

enum AiProvider { openRouter, builtIn, ollama, openAi, custom }

extension AiProviderLabel on AiProvider {
  String get label {
    switch (this) {
      case AiProvider.openRouter:
        return 'OpenRouter API';
      case AiProvider.builtIn:
        return 'Built-in (Offline)';
      case AiProvider.ollama:
        return 'Ollama (Local)';
      case AiProvider.openAi:
        return 'OpenAI API';
      case AiProvider.custom:
        return 'Custom Endpoint';
    }
  }

  String get description {
    switch (this) {
      case AiProvider.openRouter:
        return 'Access hundreds of AI models (Gemini, Claude, DeepSeek, Llama) via OpenRouter.';
      case AiProvider.builtIn:
        return 'Simple local agent, no external calls.';
      case AiProvider.ollama:
        return 'Run open-source models on your GPU via Ollama.';
      case AiProvider.openAi:
        return 'Use OpenAI GPT-4o, GPT-4-turbo, or any compatible API.';
      case AiProvider.custom:
        return 'Point to any HTTP POST endpoint that accepts { prompt } and returns { content }.';
    }
  }
}
