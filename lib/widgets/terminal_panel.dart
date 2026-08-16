import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../state/workspace_state.dart';

/// VS Code / CMD style Terminal panel with command history (Up/Down),
/// ANSI color code parsing, auto-scroll, process kill, and clear output actions.
class TerminalPanel extends StatefulWidget {
  const TerminalPanel({super.key, required this.workspaceState});

  final WorkspaceState workspaceState;

  @override
  State<TerminalPanel> createState() => _TerminalPanelState();
}

class _TerminalPanelState extends State<TerminalPanel> {
  String _activeTab = 'TERMINAL';
  final List<String> _tabs = [
    'PROBLEMS',
    'OUTPUT',
    'DEBUG CONSOLE',
    'TERMINAL',
  ];

  final _scrollController = ScrollController();
  final _inputController = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  final List<String> _commandHistory = [];
  int _historyIndex = -1;
  int _lastTerminalCols = 0;
  int _lastTerminalRows = 0;

  @override
  void initState() {
    super.initState();
    widget.workspaceState.engine.addListener(_autoScrollToBottom);
  }

  @override
  void dispose() {
    widget.workspaceState.engine.removeListener(_autoScrollToBottom);
    _scrollController.dispose();
    _inputController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _autoScrollToBottom() {
    if (_scrollController.hasClients) {
      Future.delayed(const Duration(milliseconds: 50), () {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  void _submitCommand(String cmd) {
    final trimmed = cmd.trim();
    if (trimmed.isNotEmpty) {
      _commandHistory.add(trimmed);
      _historyIndex = _commandHistory.length;
      widget.workspaceState.engine.runCommand(trimmed);
      _inputController.clear();
    }
    _focusNode.requestFocus();
  }

  void _navigateHistory(bool goUp) {
    if (_commandHistory.isEmpty) return;

    if (goUp) {
      if (_historyIndex > 0) {
        _historyIndex--;
        _inputController.text = _commandHistory[_historyIndex];
        _inputController.selection = TextSelection.collapsed(
          offset: _inputController.text.length,
        );
      }
    } else {
      if (_historyIndex < _commandHistory.length - 1) {
        _historyIndex++;
        _inputController.text = _commandHistory[_historyIndex];
        _inputController.selection = TextSelection.collapsed(
          offset: _inputController.text.length,
        );
      } else {
        _historyIndex = _commandHistory.length;
        _inputController.clear();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header / Tab Bar
          SizedBox(
            height: 34,
            child: Row(
              children: [
                Expanded(
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: _tabs.length,
                    itemBuilder: (context, index) {
                      final tab = _tabs[index];
                      final isActive = tab == _activeTab;

                      return InkWell(
                        onTap: () => setState(() => _activeTab = tab),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: BorderSide(
                                color: isActive
                                    ? const Color(0xFF007ACC)
                                    : Colors.transparent,
                                width: 2,
                              ),
                            ),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            tab,
                            style: TextStyle(
                              color: isActive
                                  ? Colors.white
                                  : const Color(0xFF8E8E8E),
                              fontSize: 11,
                              fontWeight: isActive
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),

                // Terminal Action Controls
                if (_activeTab == 'TERMINAL')
                  _TerminalHeaderAction(
                    icon: Icons.stop_circle_outlined,
                    tooltip: 'Kill Running Process (Ctrl+C)',
                    color: const Color(0xFFF44336),
                    onTap: () => widget.workspaceState.engine.killProcess(),
                  ),
                _TerminalHeaderAction(
                  icon: Icons.clear_all_rounded,
                  tooltip: _activeTab == 'TERMINAL'
                      ? 'Clear Terminal'
                      : _activeTab == 'OUTPUT'
                          ? 'Clear Output'
                          : _activeTab == 'DEBUG CONSOLE'
                              ? 'Clear Debug Console'
                              : 'Clear Problems',
                  onTap: () {
                    if (_activeTab == 'TERMINAL') {
                      widget.workspaceState.engine.clearTerminal();
                    } else if (_activeTab == 'OUTPUT') {
                      widget.workspaceState.engine.clearOutput();
                    } else if (_activeTab == 'DEBUG CONSOLE') {
                      widget.workspaceState.engine.clearDebug();
                    } else {
                      widget.workspaceState.engine.clearProblems();
                    }
                  },
                ),
                _TerminalHeaderAction(
                  icon: Icons.close_rounded,
                  tooltip: 'Close Panel',
                  onTap: widget.workspaceState.toggleTerminal,
                ),
                const SizedBox(width: 8),
              ],
            ),
          ),

          // Content Area
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                _scheduleTerminalResize(constraints);
                return Container(
                  color: const Color(0xFF0C0C0C), // CMD dark console background
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: _buildContent(),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _scheduleTerminalResize(BoxConstraints constraints) {
    if (_activeTab != 'TERMINAL') return;
    final cols = (constraints.maxWidth / 8).floor().clamp(20, 300);
    final rows = (constraints.maxHeight / 20).floor().clamp(5, 100);
    if (cols == _lastTerminalCols && rows == _lastTerminalRows) return;
    _lastTerminalCols = cols;
    _lastTerminalRows = rows;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        widget.workspaceState.engine.resizeTerminal(cols: cols, rows: rows);
      }
    });
  }

  Widget _buildContent() {
    if (_activeTab == 'TERMINAL') {
      final output = widget.workspaceState.engine.terminalOutput;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: SelectionArea(
              child: output.isEmpty
                  ? const Center(
                      child: Text(
                        'Terminal ready. Type a command or run a project task.',
                        style: TextStyle(color: Color(0xFF555555), fontSize: 12, fontFamily: 'Consolas'),
                      ),
                    )
                  : ListView.builder(
                      controller: _scrollController,
                      itemCount: output.length,
                      itemBuilder: (context, index) {
                        return RichText(text: _parseAnsiToTextSpan(output[index]));
                      },
                    ),
            ),
          ),

          const SizedBox(height: 6),

          // Active CMD Prompt Input
          Row(
            children: [
              Text(
                'PS ${widget.workspaceState.projectName}> ',
                style: const TextStyle(
                  color: Color(0xFF4EC9B0), // PowerShell cyan prompt
                  fontSize: 13,
                  fontFamily: 'Consolas',
                  fontWeight: FontWeight.w600,
                ),
              ),
              Expanded(
                child: KeyboardListener(
                  focusNode: FocusNode(),
                  onKeyEvent: (event) {
                    if (event is KeyDownEvent) {
                      if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                        _navigateHistory(true);
                      } else if (event.logicalKey ==
                          LogicalKeyboardKey.arrowDown) {
                        _navigateHistory(false);
                      }
                    }
                  },
                  child: TextField(
                    controller: _inputController,
                    focusNode: _focusNode,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontFamily: 'Consolas',
                    ),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                      hintText:
                          'Type a shell command (e.g. dir, flutter run, git status)...',
                      hintStyle: TextStyle(
                        color: Color(0xFF555555),
                        fontSize: 12,
                      ),
                    ),
                    onSubmitted: _submitCommand,
                  ),
                ),
              ),
            ],
          ),
        ],
      );
    }

    if (_activeTab == 'OUTPUT') {
      final logs = widget.workspaceState.engine.outputLogs;
      if (logs.isEmpty) {
        return const Center(
          child: Text(
            'No build or task output yet.',
            style: TextStyle(color: Color(0xFF8E8E8E), fontSize: 13),
          ),
        );
      }
      return SelectionArea(
        child: ListView.builder(
          controller: _scrollController,
          itemCount: logs.length,
          itemBuilder: (context, index) {
            return RichText(text: _parseAnsiToTextSpan(logs[index]));
          },
        ),
      );
    }

    if (_activeTab == 'DEBUG CONSOLE') {
      final debugs = widget.workspaceState.engine.debugLogs;
      if (debugs.isEmpty) {
        return const Center(
          child: Text(
            'Debug Console is active. Agent tool calls and engine traces appear here.',
            style: TextStyle(color: Color(0xFF8E8E8E), fontSize: 13),
          ),
        );
      }
      return SelectionArea(
        child: ListView.builder(
          controller: _scrollController,
          itemCount: debugs.length,
          itemBuilder: (context, index) {
            final text = debugs[index];
            Color color = const Color(0xFF9CDCFE);
            if (text.startsWith('[Tool Call]')) color = const Color(0xFF4FC3F7);
            if (text.startsWith('[Tool Result]')) color = const Color(0xFF7EE787);
            if (text.startsWith('[ERROR]')) color = const Color(0xFFF44336);
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(
                text.trimRight(),
                style: TextStyle(color: color, fontSize: 12, fontFamily: 'Consolas'),
              ),
            );
          },
        ),
      );
    }

    if (_activeTab == 'PROBLEMS') {
      final problems = widget.workspaceState.engine.problems;
      if (problems.isEmpty) {
        return const Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_circle_outline, size: 16, color: Color(0xFF7EE787)),
              SizedBox(width: 8),
              Text(
                'No problems detected in workspace.',
                style: TextStyle(color: Color(0xFF8E8E8E), fontSize: 13),
              ),
            ],
          ),
        );
      }
      return ListView.builder(
        itemCount: problems.length,
        itemBuilder: (context, index) {
          final problem = problems[index];
          final isError = problem['type'] == 'error';
          return Container(
            margin: const EdgeInsets.symmetric(vertical: 3),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: isError ? const Color(0xFFF44336).withValues(alpha: 0.4) : const Color(0xFFD19A66).withValues(alpha: 0.4),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  isError ? Icons.error_outline : Icons.warning_amber_rounded,
                  size: 16,
                  color: isError ? const Color(0xFFF44336) : const Color(0xFFD19A66),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    problem['message']?.toString() ?? 'Error',
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
              ],
            ),
          );
        },
      );
    }

    return Center(
      child: Text(
        'No ${_activeTab.toLowerCase()} to display.',
        style: const TextStyle(color: Color(0xFF8E8E8E), fontSize: 13),
      ),
    );
  }

  /// Robust ANSI and VT100 control sequence parser that strips cursor/screen codes
  /// (\x1b[K, \x1b[9;39H, \x1b[?25h, OSC sequences) and converts SGR colors to styled TextSpans.
  TextSpan _parseAnsiToTextSpan(String rawLine) {
    // 1. Strip OSC sequences: \x1b]...\x07 or \x1b]...\x1b\
    String cleaned = rawLine.replaceAll(RegExp(r'\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)'), '');

    // 2. Strip character set selections (\x1b(B, etc.)
    cleaned = cleaned.replaceAll(RegExp(r'\x1b\([a-zA-Z0-9]'), '');

    // 3. Strip all non-SGR CSI control sequences (e.g. \x1b[K, \x1b[2J, \x1b[?25h, \x1b[9;39H, etc.)
    // Matches anything starting with \x1b[ up to a command letter, EXCEPT 'm' (which is SGR color)
    cleaned = cleaned.replaceAll(RegExp(r'\x1b\[\??[0-9;]*[a-ln-zA-LN-Z]'), '');

    // 4. Strip stray non-printable control characters (bell, standalone escapes)
    cleaned = cleaned.replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1A\x1C-\x1F]'), '');

    // 5. Parse SGR color sequences: \x1b[...m
    final sgrRegex = RegExp(r'\x1b\[([0-9;]*)m');
    final matches = sgrRegex.allMatches(cleaned);

    if (matches.isEmpty) {
      Color textColor = const Color(0xFFD4D4D4);
      if (cleaned.startsWith('\$ ') || cleaned.startsWith('PS ') || cleaned.endsWith('>')) {
        textColor = const Color(0xFF4EC9B0);
      } else if (cleaned.startsWith('[SYSTEM]') || cleaned.startsWith('[Engine]')) {
        textColor = const Color(0xFF569CD6);
      } else if (cleaned.startsWith('[ERROR]') || cleaned.toLowerCase().contains('error:')) {
        textColor = const Color(0xFFF44336);
      }
      return TextSpan(
        text: cleaned,
        style: TextStyle(
          color: textColor,
          fontSize: 13,
          fontFamily: 'Consolas',
          height: 1.35,
        ),
      );
    }

    final List<TextSpan> spans = [];
    int lastEnd = 0;
    Color currentColor = const Color(0xFFD4D4D4);
    FontWeight currentWeight = FontWeight.normal;

    for (final match in matches) {
      if (match.start > lastEnd) {
        final segmentText = cleaned.substring(lastEnd, match.start);
        if (segmentText.isNotEmpty) {
          spans.add(
            TextSpan(
              text: segmentText,
              style: TextStyle(
                color: currentColor,
                fontWeight: currentWeight,
                fontSize: 13,
                fontFamily: 'Consolas',
                height: 1.35,
              ),
            ),
          );
        }
      }

      final params = match.group(1)?.split(';').map((s) => int.tryParse(s) ?? 0).toList() ?? [0];
      if (params.isEmpty) params.add(0);

      for (int i = 0; i < params.length; i++) {
        final code = params[i];
        switch (code) {
          case 0:
            currentColor = const Color(0xFFD4D4D4);
            currentWeight = FontWeight.normal;
            break;
          case 1:
            currentWeight = FontWeight.bold;
            break;
          case 2:
          case 22:
            currentWeight = FontWeight.normal;
            break;
          case 30:
            currentColor = const Color(0xFF000000);
            break;
          case 31:
          case 91:
            currentColor = const Color(0xFFF44336); // Red / Bright Red
            break;
          case 32:
          case 92:
            currentColor = const Color(0xFF4CAF50); // Green / Bright Green
            break;
          case 33:
          case 93:
            currentColor = const Color(0xFFFFEB3B); // Yellow / Bright Yellow
            break;
          case 34:
          case 94:
            currentColor = const Color(0xFF2196F3); // Blue / Bright Blue
            break;
          case 35:
          case 95:
            currentColor = const Color(0xFFAB47BC); // Magenta
            break;
          case 36:
          case 96:
            currentColor = const Color(0xFF00BCD4); // Cyan / Bright Cyan
            break;
          case 37:
          case 97:
            currentColor = Colors.white; // White
            break;
          case 39:
            currentColor = const Color(0xFFD4D4D4); // Default foreground
            break;
          case 90:
            currentColor = const Color(0xFF808080); // Gray / Bright Black
            break;
        }
      }

      lastEnd = match.end;
    }

    if (lastEnd < cleaned.length) {
      final remaining = cleaned.substring(lastEnd);
      if (remaining.isNotEmpty) {
        spans.add(
          TextSpan(
            text: remaining,
            style: TextStyle(
              color: currentColor,
              fontWeight: currentWeight,
              fontSize: 13,
              fontFamily: 'Consolas',
              height: 1.35,
            ),
          ),
        );
      }
    }

    return TextSpan(children: spans);
  }
}

class _TerminalHeaderAction extends StatelessWidget {
  const _TerminalHeaderAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.color,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: IconButton(
        icon: Icon(icon, size: 16, color: color ?? const Color(0xFF8E8E8E)),
        onPressed: onTap,
        splashRadius: 16,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
      ),
    );
  }
}
