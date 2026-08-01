import 'package:flutter/material.dart';

import '../state/workspace_state.dart';

/// VS Code-inspired Activity Sidebar with slim, refined icons and active indicators.
class ActivitySidebar extends StatelessWidget {
  const ActivitySidebar({super.key, required this.workspaceState});

  final WorkspaceState workspaceState;

  @override
  Widget build(BuildContext context) {
    const items = [
      (Icons.copy_outlined, 'Explorer'),
      (Icons.search_rounded, 'Search'),
      (Icons.account_tree_outlined, 'Source Control'),
      (Icons.grid_view_outlined, 'Extensions'),
    ];

    return Container(
      width: 48,
      decoration: BoxDecoration(
        color: const Color(0xFF181818),
        border: Border(right: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 8),
          for (final item in items)
            _ActivityIconButton(
              icon: item.$1,
              label: item.$2,
              selected: workspaceState.activeActivity == item.$2,
              onTap: () => workspaceState.setActiveActivity(item.$2),
            ),
          const Spacer(),
          _ActivityIconButton(
            icon: Icons.settings_outlined,
            label: 'Settings',
            selected: workspaceState.activeActivity == 'Settings',
            onTap: () => workspaceState.setActiveActivity('Settings'),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _ActivityIconButton extends StatefulWidget {
  const _ActivityIconButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_ActivityIconButton> createState() => _ActivityIconButtonState();
}

class _ActivityIconButtonState extends State<_ActivityIconButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final activeColor = Colors.white;
    final hoverColor = const Color(0xFFCCCCCC);
    final inactiveColor = const Color(0xFF858585);

    return Tooltip(
      message: widget.label,
      waitDuration: const Duration(milliseconds: 300),
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: InkWell(
          onTap: widget.onTap,
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
          child: SizedBox(
            height: 48,
            width: 48,
            child: Stack(
              children: [
                if (widget.selected)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      width: 2,
                      height: 48,
                      decoration: const BoxDecoration(
                        color: Color(0xFF007ACC),
                        borderRadius: BorderRadius.only(
                          topRight: Radius.circular(2),
                          bottomRight: Radius.circular(2),
                        ),
                      ),
                    ),
                  ),
                Center(
                  child: Icon(
                    widget.icon,
                    size: 21,
                    color: widget.selected
                        ? activeColor
                        : (_isHovered ? hoverColor : inactiveColor),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
