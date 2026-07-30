import 'package:flutter/material.dart';

import '../state/workspace_state.dart';

/// Fixed-width primary navigation rail with interactive controls.
class ActivitySidebar extends StatelessWidget {
  const ActivitySidebar({super.key, required this.workspaceState});

  final WorkspaceState workspaceState;

  @override
  Widget build(BuildContext context) {
    const items = [
      (Icons.folder_outlined, 'Explorer'),
      (Icons.search, 'Search'),
      (Icons.account_tree_outlined, 'Source Control'),
      (Icons.extension_outlined, 'Extensions'),
    ];

    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF333333),
        border: Border(right: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          for (final item in items)
            _ActivityIcon(
              icon: item.$1,
              label: item.$2,
              selected: workspaceState.activeActivity == item.$2,
              onTap: () => workspaceState.setActiveActivity(item.$2),
            ),
          const Spacer(),
          _ActivityIcon(
            icon: Icons.settings_outlined,
            label: 'Settings',
            selected: workspaceState.activeActivity == 'Settings',
            onTap: () => workspaceState.setActiveActivity('Settings'),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

class _ActivityIcon extends StatelessWidget {
  const _ActivityIcon({
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
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 52,
          child: Stack(
            children: [
              if (selected)
                const Align(
                  alignment: Alignment.centerLeft,
                  child: ColoredBox(color: Color(0xFF3794FF), child: SizedBox(width: 2, height: 52)),
                ),
              Center(
                child: Icon(
                  icon,
                  size: 28, // Slightly larger for iPad touch targets
                  color: selected ? Colors.white : const Color(0xFFB6B6B6),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

