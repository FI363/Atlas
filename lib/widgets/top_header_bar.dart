import 'package:flutter/material.dart';

import '../state/workspace_state.dart';

/// The top iPad header bar containing workspace title and global panel toggles.
class TopHeaderBar extends StatelessWidget {
  const TopHeaderBar({super.key, required this.workspaceState});

  final WorkspaceState workspaceState;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E), // Slightly darker header
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
      ),
      child: Row(
        children: [
          const SizedBox(width: 16),
          // Workspace Title
          const Icon(Icons.code_rounded, size: 20, color: Color(0xFF3794FF)),
          const SizedBox(width: 12),
          Text(
            'Atlas / my_flutter_project',
            style: theme.textTheme.titleMedium?.copyWith(
              fontSize: 14,
              color: const Color(0xFFCCCCCC),
            ),
          ),
          
          const Spacer(),
          
          // Action Buttons
          _HeaderButton(
            icon: Icons.play_arrow_rounded,
            tooltip: 'Run Project',
            color: const Color(0xFF4CAF50), // Green for run
            onTap: () {},
          ),
          const SizedBox(width: 8),
          _HeaderButton(
            icon: Icons.terminal_rounded,
            tooltip: 'Toggle Terminal',
            isActive: workspaceState.isTerminalVisible,
            onTap: workspaceState.toggleTerminal,
          ),
          const SizedBox(width: 8),
          _HeaderButton(
            icon: Icons.auto_awesome_rounded,
            tooltip: 'Toggle Atlas AI',
            isActive: workspaceState.isAiPanelVisible,
            onTap: workspaceState.toggleAiPanel,
          ),
          const SizedBox(width: 16),
        ],
      ),
    );
  }
}

class _HeaderButton extends StatelessWidget {
  const _HeaderButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.isActive = false,
    this.color,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool isActive;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final defaultColor = isActive ? Colors.white : const Color(0xFF8E8E8E);
    
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          hoverColor: const Color(0xFF2D2D2D),
          child: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: isActive ? const Color(0xFF37373D) : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(
              icon,
              size: 20,
              color: color ?? defaultColor,
            ),
          ),
        ),
      ),
    );
  }
}
