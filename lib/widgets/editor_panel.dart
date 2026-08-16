import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../state/workspace_state.dart';

/// An editable source surface that preserves drafts while tabs are switched,
/// showing VS Code-style dirty indicators (●) and supporting Ctrl+S and Save All.
class EditorPanel extends StatefulWidget {
  const EditorPanel({super.key, required this.workspaceState});

  final WorkspaceState workspaceState;

  @override
  State<EditorPanel> createState() => _EditorPanelState();
}

class _EditorPanelState extends State<EditorPanel> {
  final _controller = TextEditingController();
  final _editorFocusNode = FocusNode();
  final _findController = TextEditingController();
  final _replaceController = TextEditingController();
  String? _controllerFile;
  bool _showFind = false;
  bool _showReplace = false;

  @override
  void dispose() {
    _controller.dispose();
    _editorFocusNode.dispose();
    _findController.dispose();
    _replaceController.dispose();
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
        SingleActivator(LogicalKeyboardKey.keyS, control: true, shift: true): _SaveAllIntent(),
        SingleActivator(LogicalKeyboardKey.keyS, meta: true, shift: true): _SaveAllIntent(),
        SingleActivator(LogicalKeyboardKey.keyF, control: true): _FindIntent(),
        SingleActivator(LogicalKeyboardKey.keyF, meta: true): _FindIntent(),
        SingleActivator(LogicalKeyboardKey.keyH, control: true): _ReplaceIntent(),
        SingleActivator(LogicalKeyboardKey.keyH, meta: true): _ReplaceIntent(),
        SingleActivator(LogicalKeyboardKey.escape): _DismissFindIntent(),
      },
      child: Actions(
        actions: {
          _SaveIntent: CallbackAction<_SaveIntent>(
            onInvoke: (_) {
              if (activeFile != null) widget.workspaceState.saveCurrentFile();
              return null;
            },
          ),
          _SaveAllIntent: CallbackAction<_SaveAllIntent>(
            onInvoke: (_) {
              widget.workspaceState.saveAllFiles();
              return null;
            },
          ),
          _FindIntent: CallbackAction<_FindIntent>(onInvoke: (_) {
            _openFind();
            return null;
          }),
          _ReplaceIntent: CallbackAction<_ReplaceIntent>(onInvoke: (_) {
            _openFind(replace: true);
            return null;
          }),
          _DismissFindIntent: CallbackAction<_DismissFindIntent>(onInvoke: (_) {
            if (_showFind) {
              setState(() => _showFind = false);
              _editorFocusNode.requestFocus();
            }
            return null;
          }),
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
                if (widget.workspaceState.settings.breadcrumbs && activeFile != null)
                  _BreadcrumbsBar(filePath: activeFile),
                if (_showFind)
                  _FindReplaceBar(
                    findController: _findController,
                    replaceController: _replaceController,
                    showReplace: _showReplace,
                    matchCount: _matchCount,
                    onQueryChanged: () => setState(() {}),
                    onFindNext: _findNext,
                    onFindPrevious: () => _findNext(backwards: true),
                    onReplace: _replaceCurrent,
                    onReplaceAll: _replaceAll,
                    onClose: () {
                      setState(() => _showFind = false);
                      _editorFocusNode.requestFocus();
                    },
                  ),
                Expanded(
                  child: content == null
                      ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                      : _CodeEditor(
                          controller: _controller,
                          focusNode: _editorFocusNode,
                          settings: widget.workspaceState.settings,
                          onChanged: (value) => widget.workspaceState.updateDraft(activeFile!, value),
                        ),
                ),
                _EditorStatusBar(
                  isDirty: isDirty,
                  hasAnyUnsaved: widget.workspaceState.hasAnyUnsavedChanges,
                  onSave: activeFile == null ? null : () => _save(activeFile),
                  onSaveAll: widget.workspaceState.saveAllFiles,
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

  int get _matchCount {
    final query = _findController.text;
    if (query.isEmpty) return 0;
    return RegExp(RegExp.escape(query)).allMatches(_controller.text).length;
  }

  void _openFind({bool replace = false}) {
    setState(() {
      _showFind = true;
      _showReplace = replace;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _findController.selection = TextSelection(baseOffset: 0, extentOffset: _findController.text.length);
    });
  }

  void _findNext({bool backwards = false}) {
    final query = _findController.text;
    if (query.isEmpty) return;
    final text = _controller.text;
    final selection = _controller.selection;
    final start = backwards ? selection.start - 1 : selection.end;
    final index = backwards
        ? text.lastIndexOf(query, start < 0 ? text.length : start)
        : text.indexOf(query, start >= text.length ? 0 : start);
    final resolvedIndex = index == -1
        ? (backwards ? text.lastIndexOf(query) : text.indexOf(query))
        : index;
    if (resolvedIndex == -1) return;
    _controller.selection = TextSelection(
      baseOffset: resolvedIndex,
      extentOffset: resolvedIndex + query.length,
    );
    _editorFocusNode.requestFocus();
    setState(() {});
  }

  void _replaceCurrent() {
    final file = _controllerFile;
    final query = _findController.text;
    if (file == null || query.isEmpty) return;
    final selection = _controller.selection;
    if (selection.isValid && selection.start >= 0 && selection.end >= selection.start &&
        _controller.text.substring(selection.start, selection.end) == query) {
      final replacement = _replaceController.text;
      final nextText = _controller.text.replaceRange(selection.start, selection.end, replacement);
      final cursor = selection.start + replacement.length;
      _controller.value = TextEditingValue(
        text: nextText,
        selection: TextSelection.collapsed(offset: cursor),
      );
      widget.workspaceState.updateDraft(file, nextText);
    }
    _findNext();
  }

  void _replaceAll() {
    final file = _controllerFile;
    final query = _findController.text;
    if (file == null || query.isEmpty) return;
    final nextText = _controller.text.replaceAll(query, _replaceController.text);
    if (nextText == _controller.text) return;
    _controller.value = TextEditingValue(
      text: nextText,
      selection: const TextSelection.collapsed(offset: 0),
    );
    widget.workspaceState.updateDraft(file, nextText);
    setState(() {});
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

class _SaveAllIntent extends Intent {
  const _SaveAllIntent();
}

class _FindIntent extends Intent { const _FindIntent(); }
class _ReplaceIntent extends Intent { const _ReplaceIntent(); }
class _DismissFindIntent extends Intent { const _DismissFindIntent(); }

enum _CloseChoice { cancel, discard, save }

class _EmptyEditor extends StatelessWidget {
  const _EmptyEditor();

  @override
  Widget build(BuildContext context) => Container(
        color: const Color(0xFF1E1E1E),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.code_rounded, size: 48, color: Color(0xFF333333)),
              const SizedBox(height: 12),
              Text(
                'Open a file from the explorer to start editing.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 13),
              ),
              const SizedBox(height: 8),
              Text(
                'Press Ctrl+Shift+P for Command Palette',
                style: TextStyle(color: const Color(0xFF666666), fontSize: 11),
              ),
            ],
          ),
        ),
      );
}

class _EditorTabs extends StatelessWidget {
  const _EditorTabs({required this.workspaceState, required this.onClose});

  final WorkspaceState workspaceState;
  final ValueChanged<String> onClose;

  @override
  Widget build(BuildContext context) => Container(
        height: 35,
        color: const Color(0xFF252526),
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          itemCount: workspaceState.openFiles.length,
          itemBuilder: (context, index) {
            final file = workspaceState.openFiles[index];
            final isActive = file == workspaceState.activeFile;
            final isDirty = workspaceState.hasUnsavedChanges(file);
            final fileName = file.split('/').last;

            return _TabItem(
              filePath: file,
              fileName: fileName,
              isActive: isActive,
              isDirty: isDirty,
              onSelect: () => workspaceState.setActiveFile(file),
              onClose: () => onClose(file),
            );
          },
        ),
      );
}

class _TabItem extends StatefulWidget {
  const _TabItem({
    required this.filePath,
    required this.fileName,
    required this.isActive,
    required this.isDirty,
    required this.onSelect,
    required this.onClose,
  });

  final String filePath;
  final String fileName;
  final bool isActive;
  final bool isDirty;
  final VoidCallback onSelect;
  final VoidCallback onClose;

  @override
  State<_TabItem> createState() => _TabItemState();
}

class _TabItemState extends State<_TabItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onSelect,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: widget.isActive ? const Color(0xFF1E1E1E) : const Color(0xFF2D2D2D),
            border: Border(
              top: BorderSide(
                color: widget.isActive ? const Color(0xFF007ACC) : Colors.transparent,
                width: 2,
              ),
              right: BorderSide(color: Theme.of(context).dividerColor),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.fileName,
                style: TextStyle(
                  color: widget.isActive ? Colors.white : const Color(0xFF9D9D9D),
                  fontSize: 12,
                  fontStyle: widget.isDirty ? FontStyle.italic : FontStyle.normal,
                ),
              ),
              const SizedBox(width: 8),

              // Dirty indicator (●) or Close icon (×) on hover
              InkWell(
                onTap: widget.onClose,
                borderRadius: BorderRadius.circular(4),
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: Center(
                    child: widget.isDirty && !_isHovered
                        ? const Icon(Icons.circle, size: 7, color: Colors.white)
                        : const Icon(Icons.close_rounded, size: 14, color: Color(0xFF9D9D9D)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BreadcrumbsBar extends StatelessWidget {
  const _BreadcrumbsBar({required this.filePath});
  final String filePath;

  @override
  Widget build(BuildContext context) {
    final parts = filePath.split('/');
    return Container(
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      color: const Color(0xFF181818),
      child: Row(
        children: [
          for (int i = 0; i < parts.length; i++) ...[
            Text(
              parts[i],
              style: TextStyle(
                fontSize: 11,
                color: i == parts.length - 1 ? const Color(0xFFCCCCCC) : const Color(0xFF666666),
              ),
            ),
            if (i < parts.length - 1)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4),
                child: Icon(Icons.chevron_right_rounded, size: 12, color: Color(0xFF555555)),
              ),
          ],
        ],
      ),
    );
  }
}

class _CodeEditor extends StatelessWidget {
  const _CodeEditor({
    required this.controller,
    required this.focusNode,
    required this.settings,
    required this.onChanged,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final dynamic settings;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(16),
        child: TextField(
          controller: controller,
          focusNode: focusNode,
          onChanged: onChanged,
          expands: true,
          maxLines: null,
          minLines: null,
          keyboardType: TextInputType.multiline,
          textAlignVertical: TextAlignVertical.top,
          style: TextStyle(
            color: const Color(0xFFD4D4D4),
            fontFamily: settings.fontFamily,
            fontSize: settings.fontSize,
            height: 1.45,
          ),
          decoration: const InputDecoration(border: InputBorder.none, contentPadding: EdgeInsets.zero),
        ),
      );
}

class _FindReplaceBar extends StatelessWidget {
  const _FindReplaceBar({
    required this.findController,
    required this.replaceController,
    required this.showReplace,
    required this.matchCount,
    required this.onQueryChanged,
    required this.onFindNext,
    required this.onFindPrevious,
    required this.onReplace,
    required this.onReplaceAll,
    required this.onClose,
  });

  final TextEditingController findController;
  final TextEditingController replaceController;
  final bool showReplace;
  final int matchCount;
  final VoidCallback onQueryChanged;
  final VoidCallback onFindNext;
  final VoidCallback onFindPrevious;
  final VoidCallback onReplace;
  final VoidCallback onReplaceAll;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => Container(
        color: const Color(0xFF252526),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 6,
          runSpacing: 6,
          children: [
            _findField(findController, 'Find', onFindNext, onQueryChanged),
            Text('$matchCount matches', style: const TextStyle(color: Color(0xFF9D9D9D), fontSize: 11)),
            IconButton(onPressed: onFindPrevious, icon: const Icon(Icons.keyboard_arrow_up), tooltip: 'Previous match'),
            IconButton(onPressed: onFindNext, icon: const Icon(Icons.keyboard_arrow_down), tooltip: 'Next match'),
            if (showReplace) ...[
              _findField(replaceController, 'Replace', onReplace, () {}),
              TextButton(onPressed: onReplace, child: const Text('Replace')),
              TextButton(onPressed: onReplaceAll, child: const Text('All')),
            ],
            IconButton(onPressed: onClose, icon: const Icon(Icons.close_rounded), tooltip: 'Close find'),
          ],
        ),
      );

  Widget _findField(TextEditingController controller, String hint, VoidCallback onSubmitted, VoidCallback onChanged) => SizedBox(
        width: 180,
        height: 32,
        child: TextField(
          controller: controller,
          onChanged: (_) => onChanged(),
          onSubmitted: (_) => onSubmitted(),
          style: const TextStyle(color: Colors.white, fontSize: 12),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: Color(0xFF8E8E8E), fontSize: 12),
            filled: true,
            fillColor: const Color(0xFF3C3C3C),
            isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: BorderSide.none),
          ),
        ),
      );
}

class _EditorStatusBar extends StatelessWidget {
  const _EditorStatusBar({
    required this.isDirty,
    required this.hasAnyUnsaved,
    required this.onSave,
    required this.onSaveAll,
  });

  final bool isDirty;
  final bool hasAnyUnsaved;
  final VoidCallback? onSave;
  final VoidCallback onSaveAll;

  @override
  Widget build(BuildContext context) => Container(
        height: 26,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        color: const Color(0xFF007ACC), // VS Code blue status bar
        child: Row(
          children: [
            const Icon(Icons.cloud_done_outlined, size: 12, color: Colors.white),
            const SizedBox(width: 6),
            Text(
              isDirty ? '● Unsaved edits' : 'Ready',
              style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w500),
            ),
            const Spacer(),
            if (hasAnyUnsaved)
              TextButton(
                onPressed: onSaveAll,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text(
                  'Save All',
                  style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                ),
              ),
            TextButton.icon(
              onPressed: isDirty ? onSave : null,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              icon: const Icon(Icons.save_outlined, size: 13, color: Colors.white),
              label: const Text('Save (Ctrl+S)', style: TextStyle(color: Colors.white, fontSize: 11)),
            ),
          ],
        ),
      );
}
