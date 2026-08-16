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
                _TerminalHeaderAction(
                  icon: Icons.stop_circle_outlined,
                  tooltip: 'Kill Running Process (Ctrl+C)',
                  color: const Color(0xFFF44336),
                  onTap: () => widget.workspaceState.engine.killProcess(),
                ),
                _TerminalHeaderAction(
                  icon: Icons.clear_all_rounded,
                  tooltip: 'Clear Output (cls)',
                  onTap: () => widget.workspaceState.engine.clearTerminal(),
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
              child: ListView.builder(
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

    return Center(
      child: Text(
        'No ${_activeTab.toLowerCase()} to display.',
        style: const TextStyle(color: Color(0xFF8E8E8E), fontSize: 13),
      ),
    );
  }

  /// Simple ANSI color code parser (\x1b[31m, \x1b[32m, etc.) to styled TextSpan
  TextSpan _parseAnsiToTextSpan(String text) {
    // Regex for ANSI escape sequences like \x1b[31m or \u001b[0m
    final ansiRegex = RegExp(r'\x1b\[[0-9;]*m');
    final matches = ansiRegex.allMatches(text);

    if (matches.isEmpty) {
      Color textColor = const Color(0xFFCCCCCC);
      if (text.startsWith('\$ ')) textColor = const Color(0xFF569CD6);
      if (text.startsWith('[SYSTEM]')) textColor = const Color(0xFF4EC9B0);
      if (text.startsWith('[ERROR]')) textColor = const Color(0xFFF44336);
      return TextSpan(
        text: text,
        style: TextStyle(
          color: textColor,
          fontSize: 13,
          fontFamily: 'Consolas',
          height: 1.35,
        ),
      );
    }

    List<TextSpan> spans = [];
    int lastEnd = 0;
    Color currentColor = const Color(0xFFCCCCCC);

    for (final match in matches) {
      if (match.start > lastEnd) {
        spans.add(
          TextSpan(
            text: text.substring(lastEnd, match.start),
            style: TextStyle(
              color: currentColor,
              fontSize: 13,
              fontFamily: 'Consolas',
              height: 1.35,
            ),
          ),
        );
      }

      final code = text.substring(match.start, match.end);
      if (code.contains('31')) {
        currentColor = const Color(0xFFF44336); // Red
      } else if (code.contains('32')) {
        currentColor = const Color(0xFF4CAF50); // Green
      } else if (code.contains('33')) {
        currentColor = const Color(0xFFFFEB3B); // Yellow
      } else if (code.contains('34')) {
        currentColor = const Color(0xFF2196F3); // Blue
      } else if (code.contains('36')) {
        currentColor = const Color(0xFF00BCD4); // Cyan
      } else if (code.contains('0')) {
        currentColor = const Color(0xFFCCCCCC); // Reset
      }

      lastEnd = match.end;
    }

    if (lastEnd < text.length) {
      spans.add(
        TextSpan(
          text: text.substring(lastEnd),
          style: TextStyle(
            color: currentColor,
            fontSize: 13,
            fontFamily: 'Consolas',
            height: 1.35,
          ),
        ),
      );
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
