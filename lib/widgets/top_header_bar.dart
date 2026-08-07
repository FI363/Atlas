import 'package:flutter/material.dart';

import '../state/workspace_state.dart';

/// VS Code-style top bar with text menus, workspace title, and panel controls.
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
          _HeaderMenu(
            label: 'File',
            items: const ['Open Folder', 'Save', 'Save All', 'Refresh Workspace'],
            onSelected: (item) {
              if (item == 'Open Folder') workspaceState.engine.openFolder();
              if (item == 'Save') workspaceState.saveCurrentFile();
              if (item == 'Save All') workspaceState.saveAllFiles();
              if (item == 'Refresh Workspace') workspaceState.refreshWorkspace();
            },
          ),
          _HeaderMenu(
            label: 'View',
            items: const ['Explorer', 'Terminal', 'Atlas AI', 'Command Palette'],
            onSelected: (item) {
              if (item == 'Explorer') workspaceState.toggleExplorer();
              if (item == 'Terminal') workspaceState.toggleTerminal();
              if (item == 'Atlas AI') workspaceState.toggleAiPanel();
              if (item == 'Command Palette') workspaceState.toggleCommandPalette();
            },
          ),
          _HeaderMenu(
            label: 'Run',
            items: const ['Run Project', 'Stop Running Process'],
            onSelected: (item) {
              if (item == 'Run Project') workspaceState.runProject();
              if (item == 'Stop Running Process') workspaceState.engine.killProcess();
            },
          ),
          _HeaderMenu(
            label: 'Terminal',
            items: const ['Show Terminal', 'Clear Terminal', 'Reconnect Engine'],
            onSelected: (item) {
              if (item == 'Show Terminal' && !workspaceState.isTerminalVisible) {
                workspaceState.toggleTerminal();
              }
              if (item == 'Clear Terminal') workspaceState.engine.clearTerminal();
              if (item == 'Reconnect Engine') workspaceState.reconnectEngine();
            },
          ),
          _HeaderMenu(
            label: 'Tools',
            items: const ['Settings', 'Reconnect Engine'],
            onSelected: (item) {
              if (item == 'Settings') workspaceState.openSettings();
              if (item == 'Reconnect Engine') workspaceState.reconnectEngine();
            },
          ),
          const SizedBox(width: 6),
          Text(
            'Atlas / ${workspaceState.projectName}',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: Color(0xFFCCCCCC),
            ),
          ),
          const SizedBox(width: 4),
          _HeaderIconButton(
            icon: Icons.folder_open_outlined,
            tooltip: 'Open Folder',
            onTap: () => workspaceState.engine.openFolder(),
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

class _HeaderMenu extends StatelessWidget {
  const _HeaderMenu({required this.label, required this.items, required this.onSelected});

  final String label;
  final List<String> items;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: label,
      onSelected: onSelected,
      padding: EdgeInsets.zero,
      offset: const Offset(0, 30),
      color: const Color(0xFF252526),
      itemBuilder: (_) => items
          .map((item) => PopupMenuItem<String>(
                value: item,
                height: 30,
                child: Text(item, style: const TextStyle(fontSize: 12, color: Color(0xFFD4D4D4))),
              ))
          .toList(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        child: Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFFCCCCCC))),
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
