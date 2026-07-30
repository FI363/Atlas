import 'package:flutter/material.dart';

import '../state/workspace_state.dart';

/// Bottom output surface containing Terminal, Problems, and Output tabs.
class TerminalPanel extends StatefulWidget {
  const TerminalPanel({super.key, required this.workspaceState});

  final WorkspaceState workspaceState;

  @override
  State<TerminalPanel> createState() => _TerminalPanelState();
}

class _TerminalPanelState extends State<TerminalPanel> {
  String _activeTab = 'TERMINAL';
  
  final List<String> _tabs = ['PROBLEMS', 'OUTPUT', 'DEBUG CONSOLE', 'TERMINAL'];

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Terminal Header / Tab Bar
          SizedBox(
            height: 36,
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
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: BorderSide(
                                color: isActive ? const Color(0xFF3794FF) : Colors.transparent,
                                width: 2,
                              ),
                            ),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            tab,
                            style: TextStyle(
                              color: isActive ? const Color(0xFFE7E7E7) : const Color(0xFF8E8E8E),
                              fontSize: 11,
                              fontWeight: isActive ? FontWeight.w500 : FontWeight.normal,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                // Actions (Close button)
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 16, color: Color(0xFF8E8E8E)),
                  onPressed: widget.workspaceState.toggleTerminal,
                  tooltip: 'Close Panel',
                  splashRadius: 20,
                ),
                const SizedBox(width: 8),
              ],
            ),
          ),
          
          // Content Area
          Expanded(
            child: Container(
              color: const Color(0xFF181818), // Slightly darker background for terminal text
              padding: const EdgeInsets.all(12),
              child: _buildContent(),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildContent() {
    if (_activeTab == 'TERMINAL') {
      final output = widget.workspaceState.engine.terminalOutput;
      
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ListView.builder(
              itemCount: output.length,
              itemBuilder: (context, index) {
                return Text(
                  output[index],
                  style: const TextStyle(color: Color(0xFFCCCCCC), fontSize: 13, fontFamily: 'Consolas'),
                );
              },
            ),
          ),
          // Input field for terminal
          Row(
            children: [
              const Text(
                '\$ ',
                style: TextStyle(color: Colors.white, fontSize: 13, fontFamily: 'Consolas'),
              ),
              Expanded(
                child: TextField(
                  style: const TextStyle(color: Colors.white, fontSize: 13, fontFamily: 'Consolas'),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                  onSubmitted: (cmd) {
                    if (cmd.isNotEmpty) {
                      widget.workspaceState.engine.runCommand(cmd);
                    }
                  },
                ),
              ),
            ],
          ),
        ],
      );
    }
    
    // Placeholder for other tabs
    return Center(
      child: Text(
        'No ${_activeTab.toLowerCase()} to display.',
        style: const TextStyle(color: Color(0xFF8E8E8E), fontSize: 13),
      ),
    );
  }
}

