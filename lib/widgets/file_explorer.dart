import 'package:flutter/material.dart';
import '../state/workspace_state.dart';

/// VS Code-style File Explorer with active item highlighting, parent folder targeting,
/// auto-expansion, and inline file/folder creation.
class FileExplorer extends StatefulWidget {
  const FileExplorer({super.key, required this.workspaceState});

  final WorkspaceState workspaceState;

  @override
  State<FileExplorer> createState() => _FileExplorerState();
}

class _FileExplorerState extends State<FileExplorer> {
  // Track expanded directories and currently selected path
  final Set<String> _expandedDirs = {'lib'};
  String? _selectedPath;

  @override
  Widget build(BuildContext context) {
    final tree = widget.workspaceState.engine.fileTree;
    final projectName = widget.workspaceState.projectName.trim();
    final explorerTitle = projectName.isNotEmpty
        ? '📁 ${projectName.toUpperCase()}'
        : 'NO FOLDER OPEN';

    return _PanelFrame(
      title: explorerTitle,
      tooltip: widget.workspaceState.engine.cwd.isNotEmpty
          ? widget.workspaceState.engine.cwd
          : 'Workspace Explorer',
      actions: [
        IconButton(
          onPressed: () => _handleOpenFolder(context),
          icon: const Icon(Icons.folder_open_outlined, size: 17),
          tooltip: 'Open Folder',
          splashRadius: 16,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
        ),
        IconButton(
          onPressed: () => _createEntry(context, isDirectory: false),
          icon: const Icon(Icons.note_add_outlined, size: 17),
          tooltip: 'New File',
          splashRadius: 16,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
        ),
        IconButton(
          onPressed: () => _createEntry(context, isDirectory: true),
          icon: const Icon(Icons.create_new_folder_outlined, size: 17),
          tooltip: 'New Folder',
          splashRadius: 16,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
        ),
        IconButton(
          onPressed: () => widget.workspaceState.engine.requestFileTree(),
          icon: const Icon(Icons.refresh_rounded, size: 17),
          tooltip: 'Refresh Explorer',
          splashRadius: 16,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
        ),
      ],
      child: tree.isEmpty
          ? const Center(
              child: Text(
                'Connecting to workspace...',
                style: TextStyle(color: Color(0xFF8E8E8E), fontSize: 12),
              ),
            )
          : ListView(
              padding: const EdgeInsets.symmetric(vertical: 4),
              children: _buildTree(tree, 0, ''),
            ),
    );
  }

  String _getTargetFolder() {
    if (_selectedPath == null || _selectedPath!.isEmpty) return '';
    // If selected item is an expanded or tracked dir, return it
    if (_expandedDirs.contains(_selectedPath)) return _selectedPath!;
    // If it's a file path like 'lib/widgets/my_file.dart', extract folder 'lib/widgets'
    final parts = _selectedPath!.split('/');
    if (parts.length > 1) {
      parts.removeLast();
      return parts.join('/');
    }
    return '';
  }

  Future<void> _createEntry(
    BuildContext context, {
    required bool isDirectory,
  }) async {
    final targetFolder = _getTargetFolder();
    final pathController = TextEditingController();

    final entryName = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF252526),
        title: Text(
          isDirectory ? 'New Folder' : 'New File',
          style: const TextStyle(fontSize: 14, color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              targetFolder.isEmpty
                  ? 'Target: Project Root (/)'
                  : 'Target: /$targetFolder/',
              style: const TextStyle(fontSize: 11, color: Color(0xFF4EC9B0), fontFamily: 'Consolas'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: pathController,
              autofocus: true,
              style: const TextStyle(fontSize: 13, color: Colors.white, fontFamily: 'Consolas'),
              decoration: InputDecoration(
                hintText: isDirectory ? 'folder_name' : 'filename.dart',
                hintStyle: const TextStyle(color: Color(0xFF666666), fontSize: 12),
                filled: true,
                fillColor: const Color(0xFF3C3C3C),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                isDense: true,
              ),
              onSubmitted: (value) => Navigator.pop(dialogContext, value.trim()),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF8E8E8E))),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, pathController.text.trim()),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF007ACC),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
            ),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    pathController.dispose();

    if (entryName == null || entryName.isEmpty) return;

    final fullRelativePath = targetFolder.isEmpty ? entryName : '$targetFolder/$entryName';

    // Auto-expand target parent folder
    if (targetFolder.isNotEmpty) {
      _expandedDirs.add(targetFolder);
    }

    if (isDirectory) {
      _expandedDirs.add(fullRelativePath);
      widget.workspaceState.createDirectory(fullRelativePath);
    } else {
      widget.workspaceState.createFile(fullRelativePath);
      // Auto-open created file in editor
      Future.delayed(const Duration(milliseconds: 300), () {
        widget.workspaceState.openFile(fullRelativePath);
      });
    }
  }

  List<Widget> _buildTree(List<dynamic> nodes, int depth, String parentPath) {
    List<Widget> widgets = [];
    for (final node in nodes) {
      final name = node['name'] as String;
      final isDir = node['type'] == 'dir';
      final fullPath = parentPath.isEmpty ? name : '$parentPath/$name';
      final padding = 12.0 + (depth * 12.0);
      final isExpanded = _expandedDirs.contains(fullPath);
      final isSelected = _selectedPath == fullPath;

      widgets.add(
        InkWell(
          onTap: () {
            setState(() {
              _selectedPath = fullPath;
              if (isDir) {
                if (isExpanded) {
                  _expandedDirs.remove(fullPath);
                } else {
                  _expandedDirs.add(fullPath);
                }
              }
            });
            if (!isDir) {
              widget.workspaceState.openFile(fullPath);
            }
          },
          child: Container(
            padding: EdgeInsets.only(left: padding, right: 8, top: 4, bottom: 4),
            decoration: BoxDecoration(
              color: isSelected
                  ? const Color(0xFF37373D) // VS Code active row selection
                  : Colors.transparent,
              border: Border(
                left: BorderSide(
                  color: isSelected ? const Color(0xFF007ACC) : Colors.transparent,
                  width: 2,
                ),
              ),
            ),
            child: Row(
              children: [
                if (isDir)
                  Icon(
                    isExpanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_right,
                    size: 15,
                    color: const Color(0xFFCCCCCC),
                  )
                else
                  const SizedBox(width: 15),
                const SizedBox(width: 4),
                Icon(
                  isDir
                      ? (isExpanded ? Icons.folder_open_rounded : Icons.folder_rounded)
                      : _fileIcon(name),
                  size: 16,
                  color: isDir ? const Color(0xFFE8A838) : _fileColor(name),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    name,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                      color: isSelected ? Colors.white : const Color(0xFFCCCCCC),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      if (isDir && isExpanded && node['children'] != null) {
        widgets.addAll(_buildTree(List<dynamic>.from(node['children']), depth + 1, fullPath));
      }
    }
    return widgets;
  }

  IconData _fileIcon(String name) {
    if (name.endsWith('.dart')) return Icons.code_rounded;
    if (name.endsWith('.yaml') || name.endsWith('.yml')) return Icons.tune_rounded;
    if (name.endsWith('.md')) return Icons.description_outlined;
    if (name.endsWith('.json')) return Icons.data_object;
    if (name.endsWith('.js')) return Icons.javascript;
    if (name.endsWith('.lock')) return Icons.lock_outlined;
    return Icons.insert_drive_file_outlined;
  }

  Color _fileColor(String name) {
    if (name.endsWith('.dart')) return const Color(0xFF519ABA);
    if (name.endsWith('.yaml') || name.endsWith('.yml')) return const Color(0xFFE37933);
    if (name.endsWith('.md')) return const Color(0xFF4EC9B0);
    if (name.endsWith('.json')) return const Color(0xFFCBCB41);
    if (name.endsWith('.js')) return const Color(0xFFF7DF1E);
    return const Color(0xFF8E8E8E);
  }
  Future<void> _handleOpenFolder(BuildContext context) async {
    // If connected to remote engine, offer quick choice: Native Server Dialog or Enter Path directly
    final currentCwd = widget.workspaceState.engine.cwd;
    final pathController = TextEditingController(text: currentCwd);

    final selected = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF252526),
        title: const Row(
          children: [
            Icon(Icons.folder_open_rounded, size: 20, color: Color(0xFF3794FF)),
            SizedBox(width: 8),
            Text('Open Folder in Workspace', style: TextStyle(fontSize: 14, color: Colors.white, fontWeight: FontWeight.bold)),
          ],
        ),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Enter an absolute folder path on your workspace or browse via companion server:',
                style: TextStyle(fontSize: 12, color: Color(0xFFCCCCCC)),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: pathController,
                style: const TextStyle(fontSize: 13, color: Colors.white, fontFamily: 'Consolas'),
                decoration: InputDecoration(
                  hintText: 'e.g. C:\\Users\\... or /Users/...',
                  hintStyle: const TextStyle(color: Color(0xFF666666), fontSize: 12),
                  filled: true,
                  fillColor: const Color(0xFF3C3C3C),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  isDense: true,
                ),
                onSubmitted: (val) {
                  if (val.trim().isNotEmpty) {
                    Navigator.pop(dialogContext, val.trim());
                  }
                },
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(dialogContext, '__NATIVE_PICKER__');
                    },
                    icon: const Icon(Icons.desktop_windows_outlined, size: 14),
                    label: const Text('Browse Server Window', style: TextStyle(fontSize: 11)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF3794FF),
                      side: const BorderSide(color: Color(0xFF3794FF)),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF8E8E8E))),
          ),
          ElevatedButton(
            onPressed: () {
              final path = pathController.text.trim();
              if (path.isNotEmpty) {
                Navigator.pop(dialogContext, path);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF007ACC),
              foregroundColor: Colors.white,
            ),
            child: const Text('Open Path'),
          ),
        ],
      ),
    );

    if (selected == '__NATIVE_PICKER__') {
      widget.workspaceState.engine.openFolder();
    } else if (selected != null && selected.isNotEmpty) {
      widget.workspaceState.engine.openFolder(selected);
    }
  }
}

class _PanelFrame extends StatelessWidget {
  const _PanelFrame({
    required this.title,
    required this.child,
    this.tooltip,
    this.actions = const [],
  });

  final String title;
  final String? tooltip;
  final Widget child;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF252526),
        border: Border(right: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: Column(
        children: [
          SizedBox(
            height: 38,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                children: [
                  Expanded(
                    child: Tooltip(
                      message: tooltip ?? title,
                      waitDuration: const Duration(milliseconds: 500),
                      child: Text(
                        title,
                        style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          fontSize: 11,
                          letterSpacing: 0.8,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFFE0E0E0),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  ...actions,
                ],
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(child: child),
        ],
      ),
    );
  }
}
