import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../state/workspace_state.dart';

/// VS Code-style Command Palette modal (Ctrl+Shift+P).
class CommandPalette extends StatefulWidget {
  const CommandPalette({super.key, required this.workspaceState});

  final WorkspaceState workspaceState;

  @override
  State<CommandPalette> createState() => _CommandPaletteState();
}

class _CommandPaletteState extends State<CommandPalette> {
  final _controller = TextEditingController();
  int _selectedIndex = 0;

  late List<_CommandItem> _allItems;
  List<_CommandItem> _filteredItems = [];

  @override
  void initState() {
    super.initState();
    _allItems = [
      _CommandItem(
        title: 'File: Save Current File',
        shortcut: 'Ctrl+S',
        icon: Icons.save_outlined,
        action: () => widget.workspaceState.saveCurrentFile(),
      ),
      _CommandItem(
        title: 'File: Save All Files',
        shortcut: 'Ctrl+Shift+S',
        icon: Icons.save_as_outlined,
        action: () => widget.workspaceState.saveAllFiles(),
      ),
      _CommandItem(
        title: 'View: Toggle Terminal',
        shortcut: 'Ctrl+`',
        icon: Icons.terminal_outlined,
        action: () => widget.workspaceState.toggleTerminal(),
      ),
      _CommandItem(
        title: 'View: Toggle Atlas AI Panel',
        shortcut: '',
        icon: Icons.auto_awesome_outlined,
        action: () => widget.workspaceState.toggleAiPanel(),
      ),
      _CommandItem(
        title: 'View: Toggle File Explorer',
        shortcut: '',
        icon: Icons.copy_outlined,
        action: () => widget.workspaceState.toggleExplorer(),
      ),
      _CommandItem(
        title: 'Project: Run Flutter App',
        shortcut: 'F5',
        icon: Icons.play_arrow_outlined,
        action: () => widget.workspaceState.runProject(),
      ),
    ];
    _filteredItems = List.from(_allItems);
    _controller.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final query = _controller.text.trim().toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _filteredItems = List.from(_allItems);
      } else {
        _filteredItems = _allItems
            .where((item) => item.title.toLowerCase().contains(query))
            .toList();
      }
      _selectedIndex = 0;
    });
  }

  void _executeSelected() {
    if (_filteredItems.isNotEmpty && _selectedIndex < _filteredItems.length) {
      widget.workspaceState.toggleCommandPalette();
      _filteredItems[_selectedIndex].action();
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.workspaceState.toggleCommandPalette,
      child: Container(
        color: Colors.black54,
        alignment: Alignment.topCenter,
        padding: const EdgeInsets.only(top: 60),
        child: GestureDetector(
          onTap: () {}, // Prevent closing when tapping dialog content
          child: Material(
            elevation: 16,
            borderRadius: BorderRadius.circular(8),
            color: const Color(0xFF252526),
            child: SizedBox(
              width: 600,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Search bar
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: KeyboardListener(
                      focusNode: FocusNode(),
                      onKeyEvent: (event) {
                        if (event is KeyDownEvent) {
                          if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                            setState(() {
                              if (_selectedIndex < _filteredItems.length - 1) _selectedIndex++;
                            });
                          } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                            setState(() {
                              if (_selectedIndex > 0) _selectedIndex--;
                            });
                          } else if (event.logicalKey == LogicalKeyboardKey.enter) {
                            _executeSelected();
                          } else if (event.logicalKey == LogicalKeyboardKey.escape) {
                            widget.workspaceState.toggleCommandPalette();
                          }
                        }
                      },
                      child: TextField(
                        controller: _controller,
                        autofocus: true,
                        style: const TextStyle(color: Colors.white, fontSize: 14),
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.chevron_right_rounded, color: Color(0xFF007ACC)),
                          hintText: 'Type a command or search...',
                          hintStyle: const TextStyle(color: Color(0xFF8E8E8E)),
                          filled: true,
                          fillColor: const Color(0xFF3C3C3C),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(4),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          isDense: true,
                        ),
                      ),
                    ),
                  ),

                  const Divider(height: 1, color: Color(0xFF3C3C3C)),

                  // Results list
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 280),
                    child: _filteredItems.isEmpty
                        ? const Padding(
                            padding: EdgeInsets.all(16),
                            child: Text('No matching commands', style: TextStyle(color: Color(0xFF8E8E8E))),
                          )
                        : ListView.builder(
                            shrinkWrap: true,
                            itemCount: _filteredItems.length,
                            itemBuilder: (context, index) {
                              final item = _filteredItems[index];
                              final isSelected = index == _selectedIndex;

                              return InkWell(
                                onTap: () {
                                  widget.workspaceState.toggleCommandPalette();
                                  item.action();
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                  color: isSelected ? const Color(0xFF04395E) : Colors.transparent,
                                  child: Row(
                                    children: [
                                      Icon(item.icon, size: 16, color: isSelected ? Colors.white : const Color(0xFFCCCCCC)),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          item.title,
                                          style: TextStyle(
                                            color: isSelected ? Colors.white : const Color(0xFFCCCCCC),
                                            fontSize: 13,
                                          ),
                                        ),
                                      ),
                                      if (item.shortcut.isNotEmpty)
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF333333),
                                            borderRadius: BorderRadius.circular(4),
                                            border: Border.all(color: const Color(0xFF454545)),
                                          ),
                                          child: Text(
                                            item.shortcut,
                                            style: const TextStyle(color: Color(0xFF8E8E8E), fontSize: 11),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CommandItem {
  _CommandItem({
    required this.title,
    required this.shortcut,
    required this.icon,
    required this.action,
  });

  final String title;
  final String shortcut;
  final IconData icon;
  final VoidCallback action;
}
