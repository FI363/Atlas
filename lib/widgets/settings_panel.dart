import 'package:flutter/material.dart';

import '../state/atlas_settings.dart';
import '../state/workspace_state.dart';

/// Full VS Code-style Settings panel wired to all WorkspaceState settings.
/// Responsive and adaptive across screen sizes and resizable panel widths.
class SettingsPanel extends StatefulWidget {
  const SettingsPanel({super.key, required this.workspaceState});

  final WorkspaceState workspaceState;

  @override
  State<SettingsPanel> createState() => _SettingsPanelState();
}

class _SettingsPanelState extends State<SettingsPanel> {
  // ── Section expansion ────────────────────────────────────────────────────
  final Set<String> _expanded = {'Editor', 'AI Agent'};

  AtlasSettings get s => widget.workspaceState.settings;

  void _save() => widget.workspaceState.applySettings();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF1E1E1E),
      child: Column(
        children: [
          // Header
          Container(
            height: 38,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: const BoxDecoration(
              color: Color(0xFF252526),
              border: Border(bottom: BorderSide(color: Color(0xFF3C3C3C))),
            ),
            child: Row(
              children: [
                const Icon(Icons.settings_outlined, size: 16, color: Color(0xFF9D9D9D)),
                const SizedBox(width: 8),
                const Text(
                  'SETTINGS',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.0,
                    color: Color(0xFFCCCCCC),
                  ),
                ),
                const Spacer(),
                _SmallIconButton(
                  icon: Icons.close_rounded,
                  tooltip: 'Close Settings',
                  onTap: widget.workspaceState.closeSettings,
                ),
              ],
            ),
          ),

          // Content
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                _buildSection(
                  'Editor',
                  Icons.code_rounded,
                  [
                    _SliderTile(
                      label: 'Font Size',
                      value: s.fontSize,
                      min: 10.0,
                      max: 24.0,
                      divisions: 14,
                      display: '${s.fontSize.toInt()}px',
                      onChanged: (v) { s.fontSize = v; _save(); },
                    ),
                    _DropdownTile<String>(
                      label: 'Font Family',
                      value: s.fontFamily,
                      items: const ['Consolas', 'Courier New', 'Fira Code', 'JetBrains Mono', 'monospace'],
                      onChanged: (v) { if (v != null) { s.fontFamily = v; _save(); } },
                    ),
                    _StepperTile(
                      label: 'Tab Size',
                      value: s.tabSize,
                      min: 1,
                      max: 8,
                      onChanged: (v) { s.tabSize = v; _save(); },
                    ),
                    _SwitchTile(
                      label: 'Show Line Numbers',
                      subtitle: 'Display line numbers in the gutter',
                      value: s.showLineNumbers,
                      onChanged: (v) { s.showLineNumbers = v; _save(); },
                    ),
                    _SwitchTile(
                      label: 'Word Wrap',
                      subtitle: 'Wrap long lines instead of scrolling',
                      value: s.wordWrap,
                      onChanged: (v) { s.wordWrap = v; _save(); },
                    ),
                    _SwitchTile(
                      label: 'Auto Save',
                      subtitle: 'Save files automatically on every keystroke',
                      value: s.autoSave,
                      onChanged: (v) { s.autoSave = v; _save(); },
                    ),
                  ],
                ),

                _buildSection(
                  'Terminal',
                  Icons.terminal_outlined,
                  [
                    _SliderTile(
                      label: 'Terminal Font Size',
                      value: s.terminalFontSize,
                      min: 10.0,
                      max: 20.0,
                      divisions: 10,
                      display: '${s.terminalFontSize.toInt()}px',
                      onChanged: (v) { s.terminalFontSize = v; _save(); },
                    ),
                    _DropdownTile<String>(
                      label: 'Default Shell',
                      value: s.defaultShell,
                      items: const ['powershell', 'cmd', 'bash', 'zsh'],
                      onChanged: (v) { if (v != null) { s.defaultShell = v; _save(); } },
                    ),
                    _StepperTile(
                      label: 'History Limit',
                      value: s.terminalHistoryLimit,
                      min: 100,
                      max: 5000,
                      step: 100,
                      onChanged: (v) { s.terminalHistoryLimit = v; _save(); },
                    ),
                  ],
                ),

                _buildSection(
                  'Run / Build',
                  Icons.play_arrow_outlined,
                  [
                    _TextInputTile(
                      label: 'Default Run Command',
                      subtitle: 'Command executed when you press the ▶ Play button',
                      value: s.runCommand,
                      hint: 'e.g. flutter run -d chrome',
                      onChanged: (v) { s.runCommand = v; _save(); },
                    ),
                  ],
                ),

                _buildSection(
                  'AI Agent',
                  Icons.auto_awesome_outlined,
                  [
                    _ProviderSelectorTile(
                      current: s.aiProvider,
                      onChanged: (v) { s.aiProvider = v; _save(); },
                    ),
                    if (s.aiProvider == AiProvider.openRouter) ...[
                      _TextInputTile(
                        label: 'OpenRouter API Endpoint',
                        subtitle: 'OpenRouter API base URL',
                        value: s.openRouterEndpoint,
                        hint: 'https://openrouter.ai/api/v1',
                        onChanged: (v) { s.openRouterEndpoint = v; _save(); },
                      ),
                      _TextInputTile(
                        label: 'OpenRouter API Key',
                        subtitle: 'Stored securely in memory',
                        value: s.openRouterApiKey,
                        hint: 'sk-or-v1-...',
                        obscure: true,
                        onChanged: (v) { s.openRouterApiKey = v; _save(); },
                      ),
                      _TextInputTile(
                        label: 'Model Name',
                        subtitle: 'OpenRouter model ID (e.g. google/gemini-2.5-flash, anthropic/claude-3.7-sonnet, deepseek/deepseek-r1)',
                        value: s.openRouterModel,
                        hint: 'google/gemini-2.5-flash',
                        onChanged: (v) { s.openRouterModel = v; _save(); },
                      ),
                    ],
                    if (s.aiProvider == AiProvider.ollama) ...[
                      _TextInputTile(
                        label: 'Ollama Endpoint',
                        subtitle: 'Local server address (default: http://localhost:11434)',
                        value: s.ollamaEndpoint,
                        hint: 'http://localhost:11434',
                        onChanged: (v) { s.ollamaEndpoint = v; _save(); },
                      ),
                      _TextInputTile(
                        label: 'Ollama Model',
                        subtitle: 'Any model pulled via `ollama pull <model>`',
                        value: s.ollamaModel,
                        hint: 'e.g. deepseek-coder, llama3, qwen2.5-coder',
                        onChanged: (v) { s.ollamaModel = v; _save(); },
                      ),
                    ],
                    if (s.aiProvider == AiProvider.custom) ...[
                      _TextInputTile(
                        label: 'Custom Agent Endpoint',
                        subtitle: 'OpenAI-compatible /v1/chat/completions or custom POST endpoint',
                        value: s.customAgentEndpoint,
                        hint: 'http://localhost:8000/v1',
                        onChanged: (v) { s.customAgentEndpoint = v; _save(); },
                      ),
                      _TextInputTile(
                        label: 'Custom API Key (Optional)',
                        subtitle: 'Optional Bearer token or authorization header',
                        value: s.customApiKey,
                        hint: 'sk-... (optional)',
                        obscure: true,
                        onChanged: (v) { s.customApiKey = v; _save(); },
                      ),
                      _TextInputTile(
                        label: 'Custom Model Name',
                        subtitle: 'Model identifier passed to custom endpoint',
                        value: s.customModel,
                        hint: 'default or custom-model-id',
                        onChanged: (v) { s.customModel = v; _save(); },
                      ),
                    ],
                    _SliderTile(
                      label: 'Max Tokens',
                      value: s.aiMaxTokens.toDouble(),
                      min: 512,
                      max: 8192,
                      divisions: 15,
                      display: '${s.aiMaxTokens}',
                      onChanged: (v) { s.aiMaxTokens = v.toInt(); _save(); },
                    ),
                    _SliderTile(
                      label: 'Temperature',
                      value: s.aiTemperature,
                      min: 0.0,
                      max: 1.0,
                      divisions: 20,
                      display: s.aiTemperature.toStringAsFixed(2),
                      onChanged: (v) { s.aiTemperature = v; _save(); },
                    ),
                    _TextInputTile(
                      label: 'System Prompt',
                      subtitle: 'Defines the AI agent personality and role',
                      value: s.aiSystemPrompt,
                      hint: 'You are Atlas, an expert coding assistant...',
                      multiline: true,
                      onChanged: (v) { s.aiSystemPrompt = v; _save(); },
                    ),
                    _TestConnectionButton(workspaceState: widget.workspaceState),
                  ],
                ),

                _buildSection(
                  'Engine Connection',
                  Icons.cable_outlined,
                  [
                    _TextInputTile(
                      label: 'Engine WebSocket URL',
                      subtitle: 'Backend engine address (restart required)',
                      value: s.engineUrl,
                      hint: 'ws://localhost:8080',
                      onChanged: (v) { s.engineUrl = v; _save(); },
                    ),
                    _TextInputTile(
                      label: 'Engine Token',
                      subtitle: 'Must match ATLAS_ENGINE_TOKEN in backend',
                      value: s.engineToken,
                      hint: 'dev-token',
                      obscure: true,
                      onChanged: (v) { s.engineToken = v; _save(); },
                    ),
                    _ReconnectEngineButton(workspaceState: widget.workspaceState),
                    _ConnectionStatusTile(workspaceState: widget.workspaceState),
                  ],
                ),

                _buildSection(
                  'GitHub',
                  Icons.cloud_outlined,
                  [
                    _TextInputTile(
                      label: 'Personal Access Token',
                      subtitle: 'Used only for GitHub API requests and one-time repository setup',
                      value: s.githubToken,
                      hint: 'github_pat_...',
                      obscure: true,
                      onChanged: (v) { s.githubToken = v; _save(); },
                    ),
                    _GithubConnectionButton(workspaceState: widget.workspaceState),
                  ],
                ),

                _buildSection(
                  'Interface',
                  Icons.view_compact_outlined,
                  [
                    _SwitchTile(
                      label: 'Show Minimap',
                      subtitle: 'Overview panel on the right of the editor',
                      value: s.minimap,
                      onChanged: (v) { s.minimap = v; _save(); },
                    ),
                    _SwitchTile(
                      label: 'Show Breadcrumbs',
                      subtitle: 'File path breadcrumb above the editor',
                      value: s.breadcrumbs,
                      onChanged: (v) { s.breadcrumbs = v; _save(); },
                    ),
                    _SwitchTile(
                      label: 'Smooth Scrolling',
                      subtitle: 'Animated scroll in editor and terminal',
                      value: s.smoothScrolling,
                      onChanged: (v) { s.smoothScrolling = v; _save(); },
                    ),
                  ],
                ),

                const SizedBox(height: 24),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection(String title, IconData icon, List<Widget> children) {
    final isExpanded = _expanded.contains(title);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () => setState(() {
            if (isExpanded) {
              _expanded.remove(title);
            } else {
              _expanded.add(title);
            }
          }),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0xFF2D2D2D))),
            ),
            child: Row(
              children: [
                Icon(icon, size: 15, color: const Color(0xFF9D9D9D)),
                const SizedBox(width: 8),
                Text(
                  title.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                    color: Color(0xFFCCCCCC),
                  ),
                ),
                const Spacer(),
                Icon(
                  isExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                  size: 18,
                  color: const Color(0xFF666666),
                ),
              ],
            ),
          ),
        ),
        if (isExpanded) ...children,
        const SizedBox(height: 4),
      ],
    );
  }
}

// ── Responsive Tile building blocks ──────────────────────────────────────────

class _SwitchTile extends StatelessWidget {
  const _SwitchTile({
    required this.label,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFF2D2D2D))),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 12.5, color: Color(0xFFCCCCCC))),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(fontSize: 11, color: Color(0xFF666666)),
                    softWrap: true,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: const Color(0xFF007ACC),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ],
      ),
    );
  }
}

class _SliderTile extends StatelessWidget {
  const _SliderTile({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.display,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String display;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(left: 14, right: 10, top: 10, bottom: 4),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFF2D2D2D))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(fontSize: 12.5, color: Color(0xFFCCCCCC)),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF3C3C3C),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  display,
                  style: const TextStyle(fontSize: 11, color: Color(0xFF9D9D9D), fontFamily: 'Consolas'),
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: const Color(0xFF007ACC),
              inactiveTrackColor: const Color(0xFF3C3C3C),
              thumbColor: const Color(0xFF007ACC),
              overlayColor: const Color(0x1F007ACC),
              trackHeight: 2,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            ),
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              divisions: divisions,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}

class _StepperTile extends StatelessWidget {
  const _StepperTile({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.step = 1,
  });

  final String label;
  final int value;
  final int min;
  final int max;
  final int step;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFF2D2D2D))),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 12.5, color: Color(0xFFCCCCCC)),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          _SmallIconButton(
            icon: Icons.remove_rounded,
            tooltip: 'Decrease',
            onTap: value > min ? () => onChanged(value - step) : null,
          ),
          const SizedBox(width: 4),
          Container(
            width: 44,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFF3C3C3C),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '$value',
              style: const TextStyle(fontSize: 12, color: Colors.white, fontFamily: 'Consolas'),
            ),
          ),
          const SizedBox(width: 4),
          _SmallIconButton(
            icon: Icons.add_rounded,
            tooltip: 'Increase',
            onTap: value < max ? () => onChanged(value + step) : null,
          ),
        ],
      ),
    );
  }
}

class _DropdownTile<T> extends StatelessWidget {
  const _DropdownTile({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final String label;
  final T value;
  final List<T> items;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFF2D2D2D))),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 280;

          if (isNarrow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 12.5, color: Color(0xFFCCCCCC))),
                const SizedBox(height: 6),
                DropdownButtonHideUnderline(
                  child: DropdownButton<T>(
                    value: value,
                    isExpanded: true,
                    items: items.map((item) => DropdownMenuItem<T>(
                      value: item,
                      child: Text('$item', style: const TextStyle(fontSize: 12, color: Color(0xFFCCCCCC))),
                    )).toList(),
                    onChanged: onChanged,
                    style: const TextStyle(fontSize: 12, color: Color(0xFFCCCCCC)),
                    dropdownColor: const Color(0xFF3C3C3C),
                    borderRadius: BorderRadius.circular(6),
                    isDense: true,
                  ),
                ),
              ],
            );
          }

          return Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(fontSize: 12.5, color: Color(0xFFCCCCCC)),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              DropdownButtonHideUnderline(
                child: DropdownButton<T>(
                  value: value,
                  items: items.map((item) => DropdownMenuItem<T>(
                    value: item,
                    child: Text('$item', style: const TextStyle(fontSize: 12, color: Color(0xFFCCCCCC))),
                  )).toList(),
                  onChanged: onChanged,
                  style: const TextStyle(fontSize: 12, color: Color(0xFFCCCCCC)),
                  dropdownColor: const Color(0xFF3C3C3C),
                  borderRadius: BorderRadius.circular(6),
                  isDense: true,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _TextInputTile extends StatefulWidget {
  const _TextInputTile({
    required this.label,
    required this.subtitle,
    required this.value,
    required this.hint,
    required this.onChanged,
    this.obscure = false,
    this.multiline = false,
  });

  final String label;
  final String subtitle;
  final String value;
  final String hint;
  final ValueChanged<String> onChanged;
  final bool obscure;
  final bool multiline;

  @override
  State<_TextInputTile> createState() => _TextInputTileState();
}

class _TextInputTileState extends State<_TextInputTile> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.value);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFF2D2D2D))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.label, style: const TextStyle(fontSize: 12.5, color: Color(0xFFCCCCCC))),
          if (widget.subtitle.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              widget.subtitle,
              style: const TextStyle(fontSize: 11, color: Color(0xFF666666)),
              softWrap: true,
            ),
          ],
          const SizedBox(height: 8),
          TextField(
            controller: _ctrl,
            obscureText: widget.obscure,
            maxLines: widget.multiline ? 4 : 1,
            minLines: 1,
            style: const TextStyle(fontSize: 12, color: Colors.white, fontFamily: 'Consolas'),
            decoration: InputDecoration(
              hintText: widget.hint,
              hintStyle: const TextStyle(color: Color(0xFF555555), fontSize: 11.5),
              filled: true,
              fillColor: const Color(0xFF2D2D2D),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(4),
                borderSide: const BorderSide(color: Color(0xFF454545)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(4),
                borderSide: const BorderSide(color: Color(0xFF454545)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(4),
                borderSide: const BorderSide(color: Color(0xFF007ACC)),
              ),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            ),
            onChanged: widget.onChanged,
          ),
        ],
      ),
    );
  }
}

// ── AI Provider selector ────────────────────────────────────────────────────

class _ProviderSelectorTile extends StatelessWidget {
  const _ProviderSelectorTile({required this.current, required this.onChanged});

  final AiProvider current;
  final ValueChanged<AiProvider> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFF2D2D2D))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('AI Provider', style: TextStyle(fontSize: 12.5, color: Color(0xFFCCCCCC))),
          const SizedBox(height: 8),
          for (final provider in AiProvider.values)
            _ProviderOption(
              provider: provider,
              isSelected: current == provider,
              onTap: () => onChanged(provider),
            ),
        ],
      ),
    );
  }
}

class _ProviderOption extends StatelessWidget {
  const _ProviderOption({
    required this.provider,
    required this.isSelected,
    required this.onTap,
  });

  final AiProvider provider;
  final bool isSelected;
  final VoidCallback onTap;

  static const _providerIcons = {
    AiProvider.openRouter: Icons.bolt_outlined,
    AiProvider.ollama: Icons.computer_outlined,
    AiProvider.builtIn: Icons.offline_bolt_outlined,
    AiProvider.custom: Icons.webhook_outlined,
  };

  static const _providerColors = {
    AiProvider.openRouter: Color(0xFFFF9800),
    AiProvider.ollama: Color(0xFFDCDCAA),
    AiProvider.builtIn: Color(0xFF4EC9B0),
    AiProvider.custom: Color(0xFFC586C0),
  };

  @override
  Widget build(BuildContext context) {
    final color = _providerColors[provider] ?? const Color(0xFF007ACC);
    final icon = _providerIcons[provider] ?? Icons.auto_awesome_outlined;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF04395E) : const Color(0xFF2D2D2D),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected ? const Color(0xFF007ACC) : const Color(0xFF454545),
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 17, color: isSelected ? color : const Color(0xFF666666)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    provider.label,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: isSelected ? Colors.white : const Color(0xFF9D9D9D),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    provider.description,
                    style: const TextStyle(fontSize: 10.5, color: Color(0xFF666666)),
                    softWrap: true,
                  ),
                ],
              ),
            ),
            if (isSelected)
              const Icon(Icons.check_circle_rounded, size: 15, color: Color(0xFF007ACC)),
          ],
        ),
      ),
    );
  }
}

// ── Status tiles ─────────────────────────────────────────────────────────────

class _ReconnectEngineButton extends StatelessWidget {
  const _ReconnectEngineButton({required this.workspaceState});

  final WorkspaceState workspaceState;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFF2D2D2D))),
      ),
      child: ElevatedButton.icon(
        onPressed: workspaceState.reconnectEngine,
        icon: const Icon(Icons.refresh_rounded, size: 14),
        label: const Text('Reconnect Engine', style: TextStyle(fontSize: 12)),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF007ACC),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        ),
      ),
    );
  }
}

class _GithubConnectionButton extends StatelessWidget {
  const _GithubConnectionButton({required this.workspaceState});

  final WorkspaceState workspaceState;

  @override
  Widget build(BuildContext context) {
    final user = workspaceState.engine.githubUser;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFF2D2D2D))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ElevatedButton.icon(
            onPressed: () => workspaceState.engine.testGithubToken(workspaceState.settings.githubToken),
            icon: const Icon(Icons.verified_user_outlined, size: 14),
            label: const Text('Verify GitHub Token', style: TextStyle(fontSize: 12)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF24292F),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
          if (user != null) ...[
            const SizedBox(height: 6),
            Text('Connected as @${user['login']}', style: const TextStyle(fontSize: 11, color: Color(0xFF4EC9B0))),
          ],
        ],
      ),
    );
  }
}

class _ConnectionStatusTile extends StatelessWidget {
  const _ConnectionStatusTile({required this.workspaceState});
  final WorkspaceState workspaceState;

  @override
  Widget build(BuildContext context) {
    final connected = workspaceState.engine.isConnected;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFF2D2D2D))),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: connected ? const Color(0xFF4CAF50) : const Color(0xFFF44336),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              connected ? 'Engine connected' : 'Engine disconnected',
              style: TextStyle(
                fontSize: 12,
                color: connected ? const Color(0xFF4CAF50) : const Color(0xFFF44336),
              ),
            ),
          ),
          if (connected)
            Text(
              workspaceState.engine.projectName,
              style: const TextStyle(fontSize: 11, color: Color(0xFF666666), fontFamily: 'Consolas'),
            ),
        ],
      ),
    );
  }
}

class _TestConnectionButton extends StatefulWidget {
  const _TestConnectionButton({required this.workspaceState});
  final WorkspaceState workspaceState;

  @override
  State<_TestConnectionButton> createState() => _TestConnectionButtonState();
}

class _TestConnectionButtonState extends State<_TestConnectionButton> {
  String _status = '';

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFF2D2D2D))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ElevatedButton.icon(
            onPressed: () {
              setState(() => _status = 'Sending test prompt...');
              widget.workspaceState.engine.sendAiPrompt(
                'Ping! Confirm agent is alive and responding.',
                settingsPayload: {
                  'aiProvider': widget.workspaceState.settings.aiProvider.name,
                  'openRouterEndpoint': widget.workspaceState.settings.openRouterEndpoint,
                  'openRouterApiKey': widget.workspaceState.settings.openRouterApiKey,
                  'openRouterModel': widget.workspaceState.settings.openRouterModel,
                  'ollamaEndpoint': widget.workspaceState.settings.ollamaEndpoint,
                  'ollamaModel': widget.workspaceState.settings.ollamaModel,
                  'customAgentEndpoint': widget.workspaceState.settings.customAgentEndpoint,
                  'customApiKey': widget.workspaceState.settings.customApiKey,
                  'customModel': widget.workspaceState.settings.customModel,
                  'aiSystemPrompt': widget.workspaceState.settings.aiSystemPrompt,
                  'aiTemperature': widget.workspaceState.settings.aiTemperature,
                  'aiMaxTokens': widget.workspaceState.settings.aiMaxTokens,
                },
              );
              Future.delayed(const Duration(seconds: 2), () {
                if (mounted) setState(() => _status = 'Test sent — open AI Panel to check response.');
              });
            },
            icon: const Icon(Icons.science_outlined, size: 14),
            label: const Text('Test AI Connection', style: TextStyle(fontSize: 12)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF007ACC),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
            ),
          ),
          if (_status.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(_status, style: const TextStyle(fontSize: 11, color: Color(0xFF9D9D9D))),
          ],
        ],
      ),
    );
  }
}

// ── Shared icon button ────────────────────────────────────────────────────────

class _SmallIconButton extends StatelessWidget {
  const _SmallIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(icon, size: 16, color: onTap != null ? const Color(0xFF9D9D9D) : const Color(0xFF444444)),
        ),
      ),
    );
  }
}
