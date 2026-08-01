import 'package:flutter/material.dart';

import '../state/workspace_state.dart';

/// Clean top bar containing workspace title, run button, command palette trigger, and panel toggles.
class TopHeaderBar extends StatelessWidget {
  const TopHeaderBar({super.key, required this.workspaceState});

  final WorkspaceState workspaceState;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 38,
      decoration: BoxDecoration(
        color: const Color(0xFF1F1F1F),
        border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: Row(
        children: [
          const SizedBox(width: 14),
          const Icon(Icons.code_rounded, size: 17, color: Color(0xFF3794FF)),
          const SizedBox(width: 10),
          Text(
            'Atlas / ${workspaceState.projectName}',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: Color(0xFFCCCCCC),
            ),
          ),
          const Spacer(),

          // Command Palette button (Ctrl+Shift+P)
          _HeaderIconButton(
            icon: Icons.search_rounded,
            tooltip: 'Command Palette (Ctrl+Shift+P)',
            onTap: workspaceState.toggleCommandPalette,
          ),
          const SizedBox(width: 4),

          // Run Project button
          _HeaderIconButton(
            icon: Icons.play_arrow_outlined,
            tooltip: 'Run Project (flutter run)',
            color: const Color(0xFF4EC9B0),
            onTap: workspaceState.runProject,
          ),
          const SizedBox(width: 4),

          // Terminal Toggle button
          _HeaderIconButton(
            icon: Icons.terminal_outlined,
            tooltip: 'Toggle Terminal',
            isActive: workspaceState.isTerminalVisible,
            onTap: workspaceState.toggleTerminal,
          ),
          const SizedBox(width: 4),

          // AI Panel Toggle button
          _HeaderIconButton(
            icon: Icons.auto_awesome_outlined,
            tooltip: 'Toggle Atlas AI',
            isActive: workspaceState.isAiPanelVisible,
            onTap: workspaceState.toggleAiPanel,
          ),
          const SizedBox(width: 12),
        ],
      ),
    );
  }
}

class _HeaderIconButton extends StatefulWidget {
  const _HeaderIconButton({
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
  State<_HeaderIconButton> createState() => _HeaderIconButtonState();
}

class _HeaderIconButtonState extends State<_HeaderIconButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final defaultColor = widget.isActive ? Colors.white : const Color(0xFF9D9D9D);
    final hoverBg = const Color(0xFF2A2D2E);
    final activeBg = const Color(0xFF37373D);

    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(4),
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              color: widget.isActive ? activeBg : (_isHovered ? hoverBg : Colors.transparent),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Icon(
              widget.icon,
              size: 18,
              color: widget.color ?? (_isHovered ? Colors.white : defaultColor),
            ),
          ),
        ),
      ),
    );
  }
}
