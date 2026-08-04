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
  String openRouterEndpoint = 'https://openrouter.ai/api/v1';
  String openRouterApiKey = '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';
  String openRouterModel = 'google/gemini-2.5-flash';
  String ollamaEndpoint = 'http://localhost:11434';
  String ollamaModel = 'qwen3:4b';
  String openAiEndpoint = 'https://api.openai.com/v1';
  String openAiApiKey = '';
  String openAiModel = 'gpt-4o';
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
  String githubToken = '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';
  String githubUsername = 'FI363';

  // ── Theme / UI ────────────────────────────────────────────────────────────
  bool minimap = false;
  bool breadcrumbs = true;
  bool smoothScrolling = true;

  AtlasSettings();

  void applyMap(Map<String, dynamic> values) {
    fontSize = (values['fontSize'] as num?)?.toDouble() ?? fontSize;
    tabSize = (values['tabSize'] as num?)?.toInt() ?? tabSize;
    wordWrap = values['wordWrap'] as bool? ?? wordWrap;
    showLineNumbers = values['showLineNumbers'] as bool? ?? showLineNumbers;
    autoSave = values['autoSave'] as bool? ?? autoSave;
    fontFamily = values['fontFamily'] as String? ?? fontFamily;
    terminalFontSize = (values['terminalFontSize'] as num?)?.toDouble() ?? terminalFontSize;
    terminalHistoryLimit = (values['terminalHistoryLimit'] as num?)?.toInt() ?? terminalHistoryLimit;
    defaultShell = values['defaultShell'] as String? ?? defaultShell;
    runCommand = values['runCommand'] as String? ?? runCommand;
    final provider = values['aiProvider'] as String?;
    if (provider != null) {
      aiProvider = AiProvider.values.firstWhere((item) => item.name == provider, orElse: () => aiProvider);
    }
    openRouterEndpoint = values['openRouterEndpoint'] as String? ?? openRouterEndpoint;
    openRouterApiKey = values['openRouterApiKey'] as String? ?? openRouterApiKey;
    openRouterModel = values['openRouterModel'] as String? ?? openRouterModel;
    ollamaEndpoint = values['ollamaEndpoint'] as String? ?? ollamaEndpoint;
    ollamaModel = values['ollamaModel'] as String? ?? ollamaModel;
    openAiEndpoint = values['openAiEndpoint'] as String? ?? openAiEndpoint;
    openAiApiKey = values['openAiApiKey'] as String? ?? openAiApiKey;
    openAiModel = values['openAiModel'] as String? ?? openAiModel;
    customAgentEndpoint = values['customAgentEndpoint'] as String? ?? customAgentEndpoint;
    aiMaxTokens = (values['aiMaxTokens'] as num?)?.toInt() ?? aiMaxTokens;
    aiTemperature = (values['aiTemperature'] as num?)?.toDouble() ?? aiTemperature;
    aiSystemPrompt = values['aiSystemPrompt'] as String? ?? aiSystemPrompt;
    githubToken = values['githubToken'] as String? ?? githubToken;
    githubUsername = values['githubUsername'] as String? ?? githubUsername;
    engineToken = values['engineToken'] as String? ?? engineToken;
    engineUrl = values['engineUrl'] as String? ?? engineUrl;
    minimap = values['minimap'] as bool? ?? minimap;
    breadcrumbs = values['breadcrumbs'] as bool? ?? breadcrumbs;
    smoothScrolling = values['smoothScrolling'] as bool? ?? smoothScrolling;
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
