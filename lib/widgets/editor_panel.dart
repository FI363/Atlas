import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../state/workspace_state.dart';

/// An editable source surface that preserves drafts while tabs are switched.
class EditorPanel extends StatefulWidget {
  const EditorPanel({super.key, required this.workspaceState});

  final WorkspaceState workspaceState;

  @override
  State<EditorPanel> createState() => _EditorPanelState();
}

class _EditorPanelState extends State<EditorPanel> {
  final _controller = TextEditingController();
  String? _controllerFile;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.workspaceState.openFiles.isEmpty) return const _EmptyEditor();

    final activeFile = widget.workspaceState.activeFile;
    final content = activeFile == null ? null : widget.workspaceState.contentForFile(activeFile);
    final isDirty = activeFile != null && widget.workspaceState.hasUnsavedChanges(activeFile);
    _syncEditor(activeFile, content, isDirty);

    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.keyS, control: true): _SaveIntent(),
        SingleActivator(LogicalKeyboardKey.keyS, meta: true): _SaveIntent(),
      },
      child: Actions(
        actions: {
          _SaveIntent: CallbackAction<_SaveIntent>(
            onInvoke: (_) {
              if (activeFile != null && isDirty) _save(activeFile);
              return null;
            },
          ),
        },
        child: Focus(
          autofocus: true,
          child: Container(
            color: const Color(0xFF1E1E1E),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _EditorTabs(
                  workspaceState: widget.workspaceState,
                  onClose: _requestClose,
                ),
                Expanded(
                  child: content == null
                      ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                      : _CodeEditor(
                          controller: _controller,
                          onChanged: (value) => widget.workspaceState.updateDraft(activeFile!, value),
                        ),
                ),
                _EditorStatusBar(
                  isDirty: isDirty,
                  onSave: activeFile == null ? null : () => _save(activeFile),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _syncEditor(String? file, String? content, bool isDirty) {
    if (file == null || content == null || (_controllerFile == file && isDirty)) return;
    if (_controllerFile == file && _controller.text == content) return;
    _controllerFile = file;
    _controller.value = TextEditingValue(
      text: content,
      selection: const TextSelection.collapsed(offset: 0),
    );
  }

  void _save(String filePath) {
    final content = widget.workspaceState.contentForFile(filePath);
    if (content != null) widget.workspaceState.saveFile(filePath, content);
  }

  Future<void> _requestClose(String filePath) async {
    if (!widget.workspaceState.hasUnsavedChanges(filePath)) {
      widget.workspaceState.closeFile(filePath);
      return;
    }

    final choice = await showDialog<_CloseChoice>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Unsaved changes'),
        content: Text('Save changes to $filePath before closing?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, _CloseChoice.cancel),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, _CloseChoice.discard),
            child: const Text('Discard'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, _CloseChoice.save),
            child: const Text('Save & Close'),
          ),
        ],
      ),
    );

    if (choice == _CloseChoice.discard) widget.workspaceState.discardDraft(filePath);
    if (choice == _CloseChoice.save) _save(filePath);
    if (choice != null && choice != _CloseChoice.cancel) {
      widget.workspaceState.closeFile(filePath);
    }
  }
}

class _SaveIntent extends Intent {
  const _SaveIntent();
}

enum _CloseChoice { cancel, discard, save }

class _EmptyEditor extends StatelessWidget {
  const _EmptyEditor();

  @override
  Widget build(BuildContext context) => Container(
        color: const Color(0xFF1E1E1E),
        child: Center(
          child: Text('Open a file to start editing.', style: Theme.of(context).textTheme.bodySmall),
        ),
      );
}

class _EditorTabs extends StatelessWidget {
  const _EditorTabs({required this.workspaceState, required this.onClose});

  final WorkspaceState workspaceState;
  final ValueChanged<String> onClose;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 40,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          itemCount: workspaceState.openFiles.length,
          itemBuilder: (context, index) {
            final file = workspaceState.openFiles[index];
            final isActive = file == workspaceState.activeFile;
            return GestureDetector(
              onTap: () => workspaceState.setActiveFile(file),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: isActive ? const Color(0xFF1E1E1E) : const Color(0xFF2D2D2D),
                  border: Border(
                    top: BorderSide(color: isActive ? const Color(0xFF3794FF) : Colors.transparent, width: 2),
                    right: BorderSide(color: Theme.of(context).dividerColor),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(file, style: TextStyle(color: isActive ? Colors.white : const Color(0xFF9D9D9D), fontSize: 13)),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () => onClose(file),
                      child: const Icon(Icons.close_rounded, size: 14),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      );
}

class _CodeEditor extends StatelessWidget {
  const _CodeEditor({required this.controller, required this.onChanged});
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(16),
        child: TextField(
          controller: controller,
          onChanged: onChanged,
          expands: true,
          maxLines: null,
          minLines: null,
          keyboardType: TextInputType.multiline,
          textAlignVertical: TextAlignVertical.top,
          style: const TextStyle(color: Color(0xFFD4D4D4), fontFamily: 'Consolas', fontSize: 14, height: 1.45),
          decoration: const InputDecoration(border: InputBorder.none, contentPadding: EdgeInsets.zero),
        ),
      );
}

class _EditorStatusBar extends StatelessWidget {
  const _EditorStatusBar({required this.isDirty, required this.onSave});
  final bool isDirty;
  final VoidCallback? onSave;

  @override
  Widget build(BuildContext context) => Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        color: const Color(0xFF252526),
        child: Row(
          children: [
            Text(isDirty ? 'Unsaved changes' : 'Saved', style: Theme.of(context).textTheme.bodySmall),
            const Spacer(),
            TextButton.icon(
              onPressed: isDirty ? onSave : null,
              icon: const Icon(Icons.save_outlined, size: 16),
              label: const Text('Save'),
            ),
          ],
        ),
      );
}
