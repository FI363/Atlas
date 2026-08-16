import 'package:flutter/material.dart';

import '../state/workspace_state.dart';
import '../widgets/activity_sidebar.dart';
import '../widgets/ai_panel.dart';
import '../widgets/editor_panel.dart';
import '../widgets/file_explorer.dart';
import '../widgets/terminal_panel.dart';
import '../widgets/top_header_bar.dart';

/// Atlas's workspace shell. Responsive and reactive.
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

  static const _activitySidebarWidth = 72.0;
  static const _explorerWidth = 260.0;
  static const _aiPanelWidth = 340.0;
  static const _terminalHeight = 220.0;
  static const _desktopBreakpoint = 1100.0;
  static const _wideBreakpoint = 1440.0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Base responsive flags
            final isDesktop = constraints.maxWidth >= _desktopBreakpoint;
            final isWide = constraints.maxWidth >= _wideBreakpoint;

            return AnimatedBuilder(
              animation: _workspaceState,
              builder: (context, child) {
                // Visibility based on both screen size and state
                final showExplorer = isDesktop && _workspaceState.isExplorerVisible;
                final showAiPanel = isWide && _workspaceState.isAiPanelVisible;
                final showTerminal = _workspaceState.isTerminalVisible;

                return Column(
                  children: [
                    TopHeaderBar(workspaceState: _workspaceState),
                    Expanded(
                      child: Row(
                        children: [
                          SizedBox(
                            width: _activitySidebarWidth,
                            child: ActivitySidebar(workspaceState: _workspaceState),
                          ),
                          if (showExplorer)
                            SizedBox(
                              width: _explorerWidth,
                              child: FileExplorer(workspaceState: _workspaceState),
                            ),
                          Expanded(
                            child: Column(
                              children: [
                                Expanded(child: EditorPanel(workspaceState: _workspaceState)),
                                if (showTerminal)
                                  SizedBox(
                                    height: _terminalHeight, 
                                    child: TerminalPanel(workspaceState: _workspaceState),
                                  ),
                              ],
                            ),
                          ),
                          if (showAiPanel)
                            SizedBox(width: _aiPanelWidth, child: AiPanel(workspaceState: _workspaceState)),
                        ],
                      ),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}

