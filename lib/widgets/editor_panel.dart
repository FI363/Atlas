import 'package:flutter/material.dart';

import '../state/workspace_state.dart';

/// Main editor surface supporting tabs and editable file contents.
class EditorPanel extends StatefulWidget {
  const EditorPanel({super.key, required this.workspaceState});

  final WorkspaceState workspaceState;

  @override
  State<EditorPanel> createState() => _EditorPanelState();
}

class _EditorPanelState extends State<EditorPanel> {
  final Map<String, TextEditingController> _controllers = {};
  final Map<String, String> _loadedContents = {};

  @override
  void initState() {
    super.initState();
    _syncFromWorkspace();
  }

  @override
  void didUpdateWidget(covariant EditorPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncFromWorkspace();
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _syncFromWorkspace() {
    final activeFile = widget.workspaceState.activeFile;
    if (activeFile != null) {
      final content = widget.workspaceState.engine.getFileContent(activeFile);
      if (content != null && _loadedContents[activeFile] != content) {
        _ensureController(activeFile, content);
        _loadedContents[activeFile] = content;
      }
    }
  }

  TextEditingController _ensureController(
    String filePath, [
    String? initialContent,
  ]) {
    final existing = _controllers[filePath];
    if (existing != null) {
      if (initialContent != null && existing.text != initialContent) {
        existing.text = initialContent;
      }
      return existing;
    }

    final controller = TextEditingController(text: initialContent ?? '');
    _controllers[filePath] = controller;
    return controller;
  }

  void _saveActiveFile() {
    final activeFile = widget.workspaceState.activeFile;
    if (activeFile == null) return;

    final controller = _controllers[activeFile];
    if (controller == null) return;

    widget.workspaceState.engine.saveFile(activeFile, controller.text);
    _loadedContents[activeFile] = controller.text;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.workspaceState.openFiles.isEmpty) {
      return Container(
        color: const Color(0xFF1E1E1E),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.code_rounded,
                size: 42,
                color: Color(0xFF8E8E8E),
              ),
              const SizedBox(height: 12),
              Text(
                'Atlas Editor',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text(
                'Open a file to start editing.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      color: const Color(0xFF1E1E1E),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 40,
            child: Row(
              children: [
                Expanded(
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: widget.workspaceState.openFiles.length,
                    itemBuilder: (context, index) {
                      final file = widget.workspaceState.openFiles[index];
                      final isActive = file == widget.workspaceState.activeFile;

                      return GestureDetector(
                        onTap: () => widget.workspaceState.setActiveFile(file),
                        child: Container(
                          decoration: BoxDecoration(
                            color: isActive
                                ? const Color(0xFF1E1E1E)
                                : const Color(0xFF2D2D2D),
                            border: Border(
                              top: BorderSide(
                                color: isActive
                                    ? const Color(0xFF3794FF)
                                    : Colors.transparent,
                                width: 2,
                              ),
                              right: BorderSide(
                                color: Theme.of(context).dividerColor,
                              ),
                            ),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                file,
                                style: TextStyle(
                                  color: isActive
                                      ? Colors.white
                                      : const Color(0xFF9D9D9D),
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(width: 8),
                              GestureDetector(
                                onTap: () =>
                                    widget.workspaceState.closeFile(file),
                                child: Icon(
                                  Icons.close_rounded,
                                  size: 14,
                                  color: isActive
                                      ? const Color(0xFFCCCCCC)
                                      : const Color(0xFF8E8E8E),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: _saveActiveFile,
                  icon: const Icon(Icons.save_rounded, size: 16),
                  label: const Text('Save'),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFFCCCCCC),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                ),
                const SizedBox(width: 8),
              ],
            ),
          ),
          Expanded(child: _buildCodeArea()),
        ],
      ),
    );
  }

  Widget _buildCodeArea() {
    final activeFile = widget.workspaceState.activeFile;
    if (activeFile == null) {
      return const SizedBox.shrink();
    }

    final content = widget.workspaceState.engine.getFileContent(activeFile);

    if (content == null) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(height: 12),
            Text(
              'Loading file...',
              style: TextStyle(color: Color(0xFF8E8E8E), fontSize: 13),
            ),
          ],
        ),
      );
    }

    final controller = _ensureController(activeFile, content);

    return TextField(
      controller: controller,
      maxLines: null,
      expands: true,
      textAlignVertical: TextAlignVertical.top,
      keyboardType: TextInputType.multiline,
      style: const TextStyle(
        color: Color(0xFFD4D4D4),
        fontFamily: 'Consolas',
        fontSize: 14,
      ),
      decoration: const InputDecoration(
        filled: true,
        fillColor: Color(0xFF1E1E1E),
        border: InputBorder.none,
        contentPadding: EdgeInsets.all(16),
      ),
    );
  }
}
