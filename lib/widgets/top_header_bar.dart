import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../state/workspace_state.dart';
import 'connection_dialog.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Rich menu item model — supports labels, shortcuts, icons, separators,
// toggles (check-marks), and disabled state, just like VS Code.
// ─────────────────────────────────────────────────────────────────────────────

class _MenuEntry {
  final String? id;
  final String? label;
  final String? shortcut;
  final IconData? icon;
  final bool isSeparator;
  final bool enabled;
  final bool checked;

  const _MenuEntry({
    this.id,
    this.label,
    this.shortcut,
    this.icon,
    this.enabled = true,
    this.checked = false,
  }) : isSeparator = false;

  const _MenuEntry.separator()
      : id = null,
        label = null,
        shortcut = null,
        icon = null,
        isSeparator = true,
        enabled = false,
        checked = false;
}

/// A named menu definition used by the header bar.
class _MenuDef {
  final String label;
  final List<_MenuEntry> items;
  final ValueChanged<String> onSelected;

  const _MenuDef({
    required this.label,
    required this.items,
    required this.onSelected,
  });
}

/// VS Code-style top bar with text menus, workspace title, and panel controls.
/// Menus open on click and switch on hover — identical to VS Code behaviour.
class TopHeaderBar extends StatefulWidget {
  const TopHeaderBar({super.key, required this.workspaceState});

  final WorkspaceState workspaceState;

  @override
  State<TopHeaderBar> createState() => _TopHeaderBarState();
}

class _TopHeaderBarState extends State<TopHeaderBar> {
  /// Index of the currently-open menu, or null if all are closed.
  int? _activeMenuIndex;

  /// The overlay entry for the dropdown + dismiss barrier.
  OverlayEntry? _overlayEntry;

  /// Keys attached to each menu label so we can measure their position.
  final List<GlobalKey> _menuKeys = List.generate(8, (_) => GlobalKey());

  WorkspaceState get ws => widget.workspaceState;

  // ── Menu definitions ─────────────────────────────────────────────────────

  List<_MenuDef> _buildMenuDefs() => [
        // 0 — File
        _MenuDef(
          label: 'File',
          items: _fileMenuItems(),
          onSelected: _handleFileAction,
        ),
        // 1 — Edit
        _MenuDef(
          label: 'Edit',
          items: const [
            _MenuEntry(id: 'undo', label: 'Undo', shortcut: 'Ctrl+Z', icon: Icons.undo_rounded),
            _MenuEntry(id: 'redo', label: 'Redo', shortcut: 'Ctrl+Y', icon: Icons.redo_rounded),
            _MenuEntry.separator(),
            _MenuEntry(id: 'cut', label: 'Cut', shortcut: 'Ctrl+X', icon: Icons.content_cut_rounded),
            _MenuEntry(id: 'copy', label: 'Copy', shortcut: 'Ctrl+C', icon: Icons.content_copy_rounded),
            _MenuEntry(id: 'paste', label: 'Paste', shortcut: 'Ctrl+V', icon: Icons.content_paste_rounded),
            _MenuEntry.separator(),
            _MenuEntry(id: 'find', label: 'Find', shortcut: 'Ctrl+F', icon: Icons.search_rounded),
            _MenuEntry(id: 'replace', label: 'Replace', shortcut: 'Ctrl+H', icon: Icons.find_replace_rounded),
            _MenuEntry.separator(),
            _MenuEntry(id: 'find_in_files', label: 'Find in Files', shortcut: 'Ctrl+Shift+F', icon: Icons.manage_search_rounded),
            _MenuEntry(id: 'replace_in_files', label: 'Replace in Files', shortcut: 'Ctrl+Shift+H', icon: Icons.find_replace_rounded),
            _MenuEntry.separator(),
            _MenuEntry(id: 'toggle_line_comment', label: 'Toggle Line Comment', shortcut: 'Ctrl+/', icon: Icons.comment_rounded),
            _MenuEntry(id: 'toggle_block_comment', label: 'Toggle Block Comment', shortcut: 'Shift+Alt+A', icon: Icons.code_rounded),
            _MenuEntry(id: 'emmet_expand', label: 'Emmet: Expand Abbreviation', shortcut: 'Tab', icon: Icons.expand_rounded),
          ],
          onSelected: (_) {},
        ),
        // 2 — Selection
        _MenuDef(
          label: 'Selection',
          items: const [
            _MenuEntry(id: 'select_all', label: 'Select All', shortcut: 'Ctrl+A', icon: Icons.select_all_rounded),
            _MenuEntry.separator(),
            _MenuEntry(id: 'expand_selection', label: 'Expand Selection', shortcut: 'Shift+Alt+→'),
            _MenuEntry(id: 'shrink_selection', label: 'Shrink Selection', shortcut: 'Shift+Alt+←'),
            _MenuEntry.separator(),
            _MenuEntry(id: 'copy_line_up', label: 'Copy Line Up', shortcut: 'Shift+Alt+↑'),
            _MenuEntry(id: 'copy_line_down', label: 'Copy Line Down', shortcut: 'Shift+Alt+↓'),
            _MenuEntry(id: 'move_line_up', label: 'Move Line Up', shortcut: 'Alt+↑'),
            _MenuEntry(id: 'move_line_down', label: 'Move Line Down', shortcut: 'Alt+↓'),
            _MenuEntry.separator(),
            _MenuEntry(id: 'add_cursor_above', label: 'Add Cursor Above', shortcut: 'Ctrl+Alt+↑'),
            _MenuEntry(id: 'add_cursor_below', label: 'Add Cursor Below', shortcut: 'Ctrl+Alt+↓'),
          ],
          onSelected: (_) {},
        ),
        // 3 — View
        _MenuDef(
          label: 'View',
          items: [
            const _MenuEntry(id: 'command_palette', label: 'Command Palette', shortcut: 'Ctrl+Shift+P', icon: Icons.keyboard_command_key_rounded),
            const _MenuEntry(id: 'open_view', label: 'Open View…', shortcut: 'Ctrl+Q'),
            const _MenuEntry.separator(),
            _MenuEntry(id: 'explorer', label: 'Explorer', shortcut: 'Ctrl+Shift+E', icon: Icons.folder_outlined, checked: ws.isExplorerVisible),
            const _MenuEntry(id: 'search', label: 'Search', shortcut: 'Ctrl+Shift+F', icon: Icons.search_rounded),
            const _MenuEntry(id: 'git', label: 'Source Control', shortcut: 'Ctrl+Shift+G', icon: Icons.account_tree_rounded),
            const _MenuEntry.separator(),
            _MenuEntry(id: 'terminal', label: 'Terminal', shortcut: 'Ctrl+`', icon: Icons.terminal_rounded, checked: ws.isTerminalVisible),
            _MenuEntry(id: 'ai_panel', label: 'Atlas AI', shortcut: 'Ctrl+Shift+A', icon: Icons.auto_awesome_outlined, checked: ws.isAiPanelVisible),
            const _MenuEntry.separator(),
            const _MenuEntry(id: 'zen_mode', label: 'Zen Mode', shortcut: 'Ctrl+K Z', icon: Icons.fullscreen_rounded),
          ],
          onSelected: (id) {
            switch (id) {
              case 'command_palette':
                ws.toggleCommandPalette();
                break;
              case 'explorer':
                ws.toggleExplorer();
                break;
              case 'search':
                ws.setActiveActivity('Search');
                break;
              case 'git':
                ws.setActiveActivity('Git');
                break;
              case 'terminal':
                ws.toggleTerminal();
                break;
              case 'ai_panel':
                ws.toggleAiPanel();
                break;
            }
          },
        ),
        // 4 — Go
        _MenuDef(
          label: 'Go',
          items: const [
            _MenuEntry(id: 'go_back', label: 'Back', shortcut: 'Alt+←', icon: Icons.arrow_back_rounded),
            _MenuEntry(id: 'go_forward', label: 'Forward', shortcut: 'Alt+→', icon: Icons.arrow_forward_rounded),
            _MenuEntry.separator(),
            _MenuEntry(id: 'go_to_file', label: 'Go to File…', shortcut: 'Ctrl+P', icon: Icons.insert_drive_file_outlined),
            _MenuEntry(id: 'go_to_line', label: 'Go to Line…', shortcut: 'Ctrl+G', icon: Icons.format_list_numbered_rounded),
            _MenuEntry(id: 'go_to_symbol', label: 'Go to Symbol…', shortcut: 'Ctrl+Shift+O', icon: Icons.code_rounded),
            _MenuEntry.separator(),
            _MenuEntry(id: 'go_to_definition', label: 'Go to Definition', shortcut: 'F12'),
            _MenuEntry(id: 'go_to_references', label: 'Go to References', shortcut: 'Shift+F12'),
          ],
          onSelected: (_) {},
        ),
        // 5 — Run
        _MenuDef(
          label: 'Run',
          items: const [
            _MenuEntry(id: 'run_project', label: 'Run Project', shortcut: 'F5', icon: Icons.play_arrow_rounded),
            _MenuEntry(id: 'stop', label: 'Stop', shortcut: 'Shift+F5', icon: Icons.stop_rounded),
            _MenuEntry.separator(),
            _MenuEntry(id: 'run_command', label: 'Run Command…', icon: Icons.code_rounded),
          ],
          onSelected: (id) {
            if (id == 'run_project') ws.runProject();
            if (id == 'stop') ws.engine.killProcess();
          },
        ),
        // 6 — Terminal
        _MenuDef(
          label: 'Terminal',
          items: [
            const _MenuEntry(id: 'new_terminal', label: 'New Terminal', shortcut: 'Ctrl+Shift+`', icon: Icons.add_rounded),
            const _MenuEntry.separator(),
            _MenuEntry(id: 'show_terminal', label: 'Show Terminal', icon: Icons.terminal_rounded, checked: ws.isTerminalVisible),
            const _MenuEntry(id: 'clear_terminal', label: 'Clear Terminal', icon: Icons.cleaning_services_rounded),
            const _MenuEntry.separator(),
            const _MenuEntry(id: 'reconnect_engine', label: 'Reconnect Engine', icon: Icons.refresh_rounded),
          ],
          onSelected: (id) {
            switch (id) {
              case 'new_terminal':
              case 'show_terminal':
                if (!ws.isTerminalVisible) ws.toggleTerminal();
                break;
              case 'clear_terminal':
                ws.engine.clearTerminal();
                break;
              case 'reconnect_engine':
                ws.reconnectEngine();
                break;
            }
          },
        ),
        // 7 — Help
        _MenuDef(
          label: 'Help',
          items: const [
            _MenuEntry(id: 'about', label: 'About Atlas', icon: Icons.info_outline_rounded),
            _MenuEntry.separator(),
            _MenuEntry(id: 'keyboard_shortcuts', label: 'Keyboard Shortcuts', shortcut: 'Ctrl+K Ctrl+S', icon: Icons.keyboard_rounded),
            _MenuEntry(id: 'documentation', label: 'Documentation', icon: Icons.menu_book_rounded),
          ],
          onSelected: (_) {},
        ),
      ];

  // ── File menu items ──────────────────────────────────────────────────────

  List<_MenuEntry> _fileMenuItems() {
    final hasActiveFile = ws.activeFile != null;
    final hasUnsaved = ws.hasAnyUnsavedChanges;

    return [
      _MenuEntry(id: 'new_file', label: 'New Text File', shortcut: 'Ctrl+N', icon: Icons.note_add_outlined),
      _MenuEntry(id: 'new_window', label: 'New Window', shortcut: 'Ctrl+Shift+N', icon: Icons.open_in_new_rounded),
      const _MenuEntry.separator(),
      _MenuEntry(id: 'open_file', label: 'Open File…', shortcut: 'Ctrl+O', icon: Icons.file_open_outlined),
      _MenuEntry(id: 'open_folder', label: 'Open Folder…', shortcut: 'Ctrl+K Ctrl+O', icon: Icons.folder_open_outlined),
      _MenuEntry(id: 'open_recent', label: 'Open Recent', shortcut: '▸', icon: Icons.history_rounded),
      const _MenuEntry.separator(),
      _MenuEntry(id: 'save', label: 'Save', shortcut: 'Ctrl+S', icon: Icons.save_outlined, enabled: hasActiveFile),
      _MenuEntry(id: 'save_as', label: 'Save As…', shortcut: 'Ctrl+Shift+S', icon: Icons.save_as_outlined, enabled: hasActiveFile),
      _MenuEntry(id: 'save_all', label: 'Save All', shortcut: 'Ctrl+K S', icon: Icons.save_alt_rounded, enabled: hasUnsaved),
      const _MenuEntry.separator(),
      _MenuEntry(id: 'auto_save', label: 'Auto Save', icon: Icons.update_rounded, checked: ws.settings.autoSave),
      const _MenuEntry.separator(),
      _MenuEntry(id: 'preferences', label: 'Preferences', shortcut: '▸', icon: Icons.settings_outlined),
      const _MenuEntry.separator(),
      _MenuEntry(id: 'revert_file', label: 'Revert File', icon: Icons.undo_rounded, enabled: hasActiveFile && hasUnsaved),
      _MenuEntry(id: 'close_editor', label: 'Close Editor', shortcut: 'Ctrl+F4', icon: Icons.close_rounded, enabled: hasActiveFile),
      _MenuEntry(id: 'close_folder', label: 'Close Folder', shortcut: 'Ctrl+K F', icon: Icons.folder_off_outlined),
      const _MenuEntry.separator(),
      _MenuEntry(id: 'refresh_workspace', label: 'Refresh Workspace', icon: Icons.refresh_rounded),
    ];
  }

  void _handleFileAction(String id) {
    switch (id) {
      case 'new_file':
        ws.toggleCommandPalette();
        break;
      case 'open_file':
        ws.toggleCommandPalette();
        break;
      case 'open_folder':
        ws.toggleCommandPalette();
        break;
      case 'save':
        ws.saveCurrentFile();
        break;
      case 'save_as':
        ws.saveCurrentFile();
        break;
      case 'save_all':
        ws.saveAllFiles();
        break;
      case 'auto_save':
        ws.settings.autoSave = !ws.settings.autoSave;
        ws.applySettings();
        break;
      case 'preferences':
        ws.openSettings();
        break;
      case 'revert_file':
        final active = ws.activeFile;
        if (active != null) ws.discardDraft(active);
        break;
      case 'close_editor':
        final active = ws.activeFile;
        if (active != null) ws.closeFile(active);
        break;
      case 'refresh_workspace':
        ws.refreshWorkspace();
        break;
    }
  }

  // ── Overlay management ───────────────────────────────────────────────────

  void _showMenu(int index) {
    // Remove old overlay if switching menus.
    _overlayEntry?.remove();
    _overlayEntry = null;

    final key = _menuKeys[index];
    final renderBox = key.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final pos = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;
    final menus = _buildMenuDefs();
    final menuDef = menus[index];

    _overlayEntry = OverlayEntry(
      builder: (ctx) => Stack(
        children: [
          // ── Dismiss barrier (below header bar so label hover still works) ──
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _hideMenu,
              onSecondaryTap: _hideMenu,
            ),
          ),
          // ── Dropdown ─────────────────────────────────────────────────────
          Positioned(
            left: pos.dx,
            top: pos.dy + size.height + 2,
            child: _MenuDropdown(
              items: menuDef.items,
              onSelected: (id) {
                _hideMenu();
                menuDef.onSelected(id);
              },
            ),
          ),
        ],
      ),
    );

    Overlay.of(context).insert(_overlayEntry!);
    setState(() => _activeMenuIndex = index);
  }

  void _hideMenu() {
    _overlayEntry?.remove();
    _overlayEntry = null;
    if (mounted) setState(() => _activeMenuIndex = null);
  }

  void _onLabelTap(int index) {
    if (_activeMenuIndex == index) {
      _hideMenu();
    } else {
      _showMenu(index);
    }
  }

  void _onLabelHover(int index) {
    // Only switch on hover if a menu is already open (VS Code behaviour).
    if (_activeMenuIndex != null && _activeMenuIndex != index) {
      _showMenu(index);
    }
  }

  @override
  void dispose() {
    _overlayEntry?.remove();
    super.dispose();
  }

  // ── Build ────────────────────────────────────────────────────────────────

  Widget _buildMenuLabel(int index, String label) {
    final isActive = _activeMenuIndex == index;

    return MouseRegion(
      onEnter: (_) => _onLabelHover(index),
      child: GestureDetector(
        onTap: () => _onLabelTap(index),
        child: Container(
          key: _menuKeys[index],
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: isActive ? const Color(0xFF37373D) : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: isActive ? Colors.white : const Color(0xFFCCCCCC),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isConnected = ws.engine.isConnected;
    final menus = _buildMenuDefs();

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

          // Menu labels
          for (int i = 0; i < menus.length; i++) _buildMenuLabel(i, menus[i].label),

          const SizedBox(width: 6),
          const Spacer(),

          // Connection status badge / pairing trigger
          _ConnectionStatusBadge(
            isConnected: isConnected,
            onTap: () => ConnectionDialog.show(context, ws),
          ),
          const SizedBox(width: 8),

          // Command Palette button (Ctrl+Shift+P)
          _HeaderIconButton(
            icon: Icons.search_rounded,
            tooltip: 'Command Palette (Ctrl+Shift+P / Cmd+Shift+P)',
            onTap: ws.toggleCommandPalette,
          ),
          const SizedBox(width: 4),

          // Run Project button
          _HeaderIconButton(
            icon: Icons.play_arrow_outlined,
            tooltip: 'Run Project (flutter run)',
            color: const Color(0xFF4EC9B0),
            onTap: ws.runProject,
          ),
          const SizedBox(width: 4),

          // Terminal Toggle button
          _HeaderIconButton(
            icon: Icons.terminal_outlined,
            tooltip: 'Toggle Terminal',
            isActive: ws.isTerminalVisible,
            onTap: ws.toggleTerminal,
          ),
          const SizedBox(width: 4),

          // AI Panel Toggle button
          _HeaderIconButton(
            icon: Icons.auto_awesome_outlined,
            tooltip: 'Toggle Atlas AI',
            isActive: ws.isAiPanelVisible,
            onTap: ws.toggleAiPanel,
          ),
          const SizedBox(width: 12),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _MenuDropdown — The actual VS Code-style dropdown rendered in the overlay.
// ─────────────────────────────────────────────────────────────────────────────

class _MenuDropdown extends StatelessWidget {
  const _MenuDropdown({required this.items, required this.onSelected});

  final List<_MenuEntry> items;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(minWidth: 220),
        decoration: BoxDecoration(
          color: const Color(0xFF252526),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xFF454545), width: 0.5),
          boxShadow: const [
            BoxShadow(color: Colors.black54, blurRadius: 16, offset: Offset(0, 4)),
          ],
        ),
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: IntrinsicWidth(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: items.map((item) {
              if (item.isSeparator) {
                return Container(
                  height: 1,
                  margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                  color: const Color(0xFF454545),
                );
              }
              return _MenuItemRow(item: item, onTap: onSelected);
            }).toList(),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _MenuItemRow — A single interactive row inside the dropdown.
// ─────────────────────────────────────────────────────────────────────────────

class _MenuItemRow extends StatefulWidget {
  const _MenuItemRow({required this.item, required this.onTap});

  final _MenuEntry item;
  final ValueChanged<String> onTap;

  @override
  State<_MenuItemRow> createState() => _MenuItemRowState();
}

class _MenuItemRowState extends State<_MenuItemRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final enabled = item.enabled;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: enabled ? () => widget.onTap(item.id!) : null,
        child: Container(
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          color: (_hovered && enabled) ? const Color(0xFF04395E) : Colors.transparent,
          child: Row(
            children: [
              // Check-mark column
              SizedBox(
                width: 20,
                child: item.checked
                    ? const Icon(Icons.check_rounded, size: 14, color: Color(0xFF3794FF))
                    : null,
              ),
              // Icon column
              if (item.icon != null) ...[
                Icon(item.icon, size: 15,
                    color: enabled ? const Color(0xFFB0B0B0) : const Color(0xFF5A5A5A)),
                const SizedBox(width: 8),
              ],
              // Label
              Expanded(
                child: Text(
                  item.label ?? '',
                  style: TextStyle(
                    fontSize: 12,
                    color: enabled ? const Color(0xFFD4D4D4) : const Color(0xFF6A6A6A),
                  ),
                ),
              ),
              // Shortcut
              if (item.shortcut != null) ...[
                const SizedBox(width: 24),
                Text(
                  item.shortcut!,
                  style: TextStyle(
                    fontSize: 11,
                    color: enabled ? const Color(0xFF858585) : const Color(0xFF4A4A4A),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Connection status badge
// ─────────────────────────────────────────────────────────────────────────────

class _ConnectionStatusBadge extends StatelessWidget {
  const _ConnectionStatusBadge({required this.isConnected, required this.onTap});

  final bool isConnected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bg = isConnected ? const Color(0xFF1B3D2F) : const Color(0xFF3D261B);
    final fg = isConnected ? const Color(0xFF4EC9B0) : const Color(0xFFCE9178);

    return Tooltip(
      message: isConnected
          ? 'Connected to Atlas Engine (Tap to configure)'
          : 'Disconnected from Engine (Tap to pair)',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: fg.withAlpha(120), width: 0.8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: fg,
                ),
              ),
              const SizedBox(width: 5),
              Text(
                isConnected ? 'Engine Online' : 'Engine Offline',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: fg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Header icon button (right-side toolbar)
// ─────────────────────────────────────────────────────────────────────────────

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
