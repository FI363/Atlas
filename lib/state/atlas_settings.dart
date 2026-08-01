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
  AiProvider aiProvider = AiProvider.builtIn;
  String ollamaEndpoint = 'http://localhost:11434';
  String ollamaModel = 'deepseek-coder';
  String openAiEndpoint = 'https://api.openai.com/v1';
  String openAiApiKey = '';
  String openAiModel = 'gpt-4o';
  String customAgentEndpoint = '';
  int aiMaxTokens = 4096;
  double aiTemperature = 0.2;
  String aiSystemPrompt =
      'You are Atlas, an expert software engineering AI agent embedded in a Flutter-based code editor. '
      'Your job is to assist the developer by analysing code, finding bugs, writing tests, and explaining concepts clearly. '
      'Keep answers concise and include runnable code examples.';

  // ── Engine ────────────────────────────────────────────────────────────────
  String engineToken = 'dev-token';
  String engineUrl = 'ws://localhost:8080';

  // ── Theme / UI ────────────────────────────────────────────────────────────
  bool minimap = false;
  bool breadcrumbs = true;
  bool smoothScrolling = true;

  AtlasSettings();
}

enum AiProvider { builtIn, ollama, openAi, custom }

extension AiProviderLabel on AiProvider {
  String get label {
    switch (this) {
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
