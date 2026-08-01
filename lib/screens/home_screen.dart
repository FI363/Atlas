import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../state/workspace_state.dart';
import '../widgets/activity_sidebar.dart';
import '../widgets/ai_panel.dart';
import '../widgets/command_palette.dart';
import '../widgets/editor_panel.dart';
import '../widgets/file_explorer.dart';
import '../widgets/git_panel.dart';
import '../widgets/search_panel.dart';
import '../widgets/settings_panel.dart';
import '../widgets/terminal_panel.dart';
import '../widgets/top_header_bar.dart';

/// Atlas's workspace shell. Features VS Code-style resizable panel splitters and shortcuts.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _workspaceState = WorkspaceState();

  @override
  void dispose() {
    _workspaceState.dispose();
    super.dispose();
  }

  static const _activitySidebarWidth = 48.0;
  static const _tabletBreakpoint = 700.0;
  static const _wideBreakpoint = 1250.0;

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.keyP, control: true, shift: true): _CommandPaletteIntent(),
        SingleActivator(LogicalKeyboardKey.keyP, meta: true, shift: true): _CommandPaletteIntent(),
      },
      child: Actions(
        actions: {
          _CommandPaletteIntent: CallbackAction<_CommandPaletteIntent>(
            onInvoke: (_) {
              _workspaceState.toggleCommandPalette();
              return null;
            },
          ),
        },
        child: Scaffold(
          body: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isTablet = constraints.maxWidth >= _tabletBreakpoint;
                final isWide = constraints.maxWidth >= _wideBreakpoint;

                return AnimatedBuilder(
                  animation: _workspaceState,
                  builder: (context, child) {
                    final showExplorer = isTablet && _workspaceState.isExplorerVisible;
                    final showDockedAiPanel = isWide && _workspaceState.isAiPanelVisible;
                    final showOverlayAiPanel = !isWide && _workspaceState.isAiPanelVisible;
                    final overlayAiWidth = (constraints.maxWidth - _activitySidebarWidth)
                        .clamp(0.0, _workspaceState.aiPanelWidth)
                        .toDouble();
                    final showTerminal = _workspaceState.isTerminalVisible;

                    Widget? activeSidebarWidget;
                    if (_workspaceState.isSettingsPanelVisible) {
                      activeSidebarWidget = SettingsPanel(workspaceState: _workspaceState);
                    } else if (showExplorer) {
                      switch (_workspaceState.activeActivity) {
                        case 'Search':
                          activeSidebarWidget = SearchPanel(workspaceState: _workspaceState);
                        case 'Source Control':
                          activeSidebarWidget = GitPanel(workspaceState: _workspaceState);
                        case 'Explorer':
                        default:
                          activeSidebarWidget = FileExplorer(workspaceState: _workspaceState);
                      }
                    }

                    return Stack(
                      children: [
                        Column(
                          children: [
                            TopHeaderBar(workspaceState: _workspaceState),
                            Expanded(
                              child: Stack(
                                children: [
                                  Row(
                                    children: [
                                      SizedBox(
                                        width: _activitySidebarWidth,
                                        child: ActivitySidebar(workspaceState: _workspaceState),
                                      ),
                                      if (activeSidebarWidget != null) ...[
                                        SizedBox(
                                          width: _workspaceState.isSettingsPanelVisible
                                              ? _workspaceState.explorerWidth + 80
                                              : _workspaceState.explorerWidth,
                                          child: activeSidebarWidget,
                                        ),
                                        _HorizontalSplitter(
                                          onDrag: (dx) => _workspaceState
                                              .setExplorerWidth(_workspaceState.explorerWidth + dx),
                                        ),
                                      ],
                                      Expanded(
                                        child: Column(
                                          children: [
                                            Expanded(child: EditorPanel(workspaceState: _workspaceState)),
                                            if (showTerminal) ...[
                                              _VerticalSplitter(
                                                onDrag: (dy) => _workspaceState.setTerminalHeight(
                                                    _workspaceState.terminalHeight - dy),
                                              ),
                                              SizedBox(
                                                height: _workspaceState.terminalHeight,
                                                child: TerminalPanel(workspaceState: _workspaceState),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                      if (showDockedAiPanel) ...[
                                        _HorizontalSplitter(
                                          onDrag: (dx) => _workspaceState
                                              .setAiPanelWidth(_workspaceState.aiPanelWidth - dx),
                                        ),
                                        SizedBox(
                                          width: _workspaceState.aiPanelWidth,
                                          child: AiPanel(workspaceState: _workspaceState),
                                        ),
                                      ],
                                    ],
                                  ),
                                  if (showOverlayAiPanel)
                                    Positioned(
                                      top: 0,
                                      right: 0,
                                      bottom: 0,
                                      width: overlayAiWidth,
                                      child: Material(
                                        elevation: 12,
                                        child: AiPanel(workspaceState: _workspaceState),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        if (_workspaceState.isCommandPaletteVisible)
                          CommandPalette(workspaceState: _workspaceState),
                      ],
                    );
                  },
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _CommandPaletteIntent extends Intent {
  const _CommandPaletteIntent();
}

class _HorizontalSplitter extends StatefulWidget {
  const _HorizontalSplitter({required this.onDrag});
  final ValueChanged<double> onDrag;

  @override
  State<_HorizontalSplitter> createState() => _HorizontalSplitterState();
}

class _HorizontalSplitterState extends State<_HorizontalSplitter> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onHorizontalDragUpdate: (details) => widget.onDrag(details.delta.dx),
        child: Container(
          width: 4,
          color: _isHovered ? const Color(0xFF007ACC) : Colors.transparent,
        ),
      ),
    );
  }
}

class _VerticalSplitter extends StatefulWidget {
  const _VerticalSplitter({required this.onDrag});
  final ValueChanged<double> onDrag;

  @override
  State<_VerticalSplitter> createState() => _VerticalSplitterState();
}

class _VerticalSplitterState extends State<_VerticalSplitter> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeRow,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onVerticalDragUpdate: (details) => widget.onDrag(details.delta.dy),
        child: Container(
          height: 4,
          color: _isHovered ? const Color(0xFF007ACC) : Colors.transparent,
        ),
      ),
    );
  }
}
