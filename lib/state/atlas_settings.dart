import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// All persistent Atlas user settings. Passed to WorkspaceState and widgets
/// so every part of the app can react to changes without rebuilding the whole tree.
class AtlasSettings {
  // ── Engine & Host ─────────────────────────────────────────────────────────
  String engineToken = '';
  String engineUrl = 'ws://localhost:8080';
  List<String> recentEngineUrls = [];

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
  String ollamaModel = 'deepseek-coder';
  String openAiEndpoint = 'https://api.openai.com/v1';
  String openAiApiKey = '';
  String openAiModel = 'gpt-4o';
  String anthropicEndpoint = 'https://api.anthropic.com/v1';
  String anthropicApiKey = '';
  String anthropicModel = 'claude-3-5-sonnet-20241022';
  String geminiApiKey = '';
  String geminiModel = 'gemini-2.0-flash';
  String deepseekEndpoint = 'https://api.deepseek.com';
  String deepseekApiKey = '';
  String deepseekModel = 'deepseek-chat';
  String groqEndpoint = 'https://api.groq.com/openai/v1';
  String groqApiKey = '';
  String groqModel = 'llama-3.3-70b-versatile';
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

  // ── GitHub Integration ───────────────────────────────────────────────────
  String githubToken = '';
  String githubUsername = 'FI363';

  // ── Theme / UI ────────────────────────────────────────────────────────────
  bool minimap = false;
  bool breadcrumbs = true;
  bool smoothScrolling = true;

  AtlasSettings();

  Future<void> loadPersistedPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedUrl = prefs.getString('atlas_engine_url');
      final savedToken = prefs.getString('atlas_engine_token');
      final savedRecents = prefs.getStringList('atlas_recent_engine_urls');
      final savedSettingsJson = prefs.getString('atlas_user_settings');

      if (savedUrl != null && savedUrl.trim().isNotEmpty) {
        engineUrl = savedUrl.trim();
      }
      if (savedToken != null && savedToken.trim().isNotEmpty) {
        engineToken = savedToken.trim();
      }
      if (savedRecents != null) {
        recentEngineUrls = savedRecents;
      }
      if (savedSettingsJson != null) {
        final decoded = jsonDecode(savedSettingsJson);
        if (decoded is Map<String, dynamic>) {
          applyMap(decoded);
        }
      }
    } catch (_) {}
  }

  Future<void> persistPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('atlas_engine_url', engineUrl);
      await prefs.setString('atlas_engine_token', engineToken);
      await prefs.setStringList('atlas_recent_engine_urls', recentEngineUrls);
      await prefs.setString('atlas_user_settings', jsonEncode(toMap()));
    } catch (_) {}
  }

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
    if (values['anthropicEndpoint'] is String) anthropicEndpoint = values['anthropicEndpoint'] as String;
    if (values['anthropicApiKey'] is String) anthropicApiKey = values['anthropicApiKey'] as String;
    if (values['anthropicModel'] is String) anthropicModel = values['anthropicModel'] as String;
    if (values['geminiApiKey'] is String) geminiApiKey = values['geminiApiKey'] as String;
    if (values['geminiModel'] is String) geminiModel = values['geminiModel'] as String;
    if (values['deepseekEndpoint'] is String) deepseekEndpoint = values['deepseekEndpoint'] as String;
    if (values['deepseekApiKey'] is String) deepseekApiKey = values['deepseekApiKey'] as String;
    if (values['deepseekModel'] is String) deepseekModel = values['deepseekModel'] as String;
    if (values['groqEndpoint'] is String) groqEndpoint = values['groqEndpoint'] as String;
    if (values['groqApiKey'] is String) groqApiKey = values['groqApiKey'] as String;
    if (values['groqModel'] is String) groqModel = values['groqModel'] as String;
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
      'anthropicEndpoint': anthropicEndpoint,
      'anthropicApiKey': anthropicApiKey,
      'anthropicModel': anthropicModel,
      'geminiApiKey': geminiApiKey,
      'geminiModel': geminiModel,
      'deepseekEndpoint': deepseekEndpoint,
      'deepseekApiKey': deepseekApiKey,
      'deepseekModel': deepseekModel,
      'groqEndpoint': groqEndpoint,
      'groqApiKey': groqApiKey,
      'groqModel': groqModel,
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

enum AiProvider { openRouter, builtIn, ollama, openAi, anthropic, gemini, deepseek, groq, custom }

extension AiProviderLabel on AiProvider {
  String get label {
    switch (this) {
      case AiProvider.openRouter:
        return 'OpenRouter';
      case AiProvider.anthropic:
        return 'Anthropic (Claude)';
      case AiProvider.gemini:
        return 'Google Gemini';
      case AiProvider.deepseek:
        return 'DeepSeek';
      case AiProvider.groq:
        return 'Groq (Ultra-Fast)';
      case AiProvider.openAi:
        return 'OpenAI';
      case AiProvider.ollama:
        return 'Ollama (Local)';
      case AiProvider.builtIn:
        return 'Built-in (Offline)';
      case AiProvider.custom:
        return 'Custom API';
    }
  }

  String get description {
    switch (this) {
      case AiProvider.openRouter:
        return 'Access Gemini, Claude, DeepSeek, and Llama through OpenRouter API.';
      case AiProvider.anthropic:
        return 'Direct Anthropic Claude 3.5 Sonnet / Claude 3.7.';
      case AiProvider.gemini:
        return 'Direct Google Gemini 2.0 Flash / Pro.';
      case AiProvider.deepseek:
        return 'Direct DeepSeek V3 / R1 reasoning API.';
      case AiProvider.groq:
        return 'Ultra-low latency Llama-3.3-70B inference via Groq.';
      case AiProvider.openAi:
        return 'OpenAI GPT-4o, GPT-4o-mini, o1/o3-mini.';
      case AiProvider.ollama:
        return 'Run open-source models locally on your GPU/CPU.';
      case AiProvider.builtIn:
        return 'Simple offline local agent for file manipulation.';
      case AiProvider.custom:
        return 'Any OpenAI-compatible or custom HTTP endpoint.';
    }
  }
}
