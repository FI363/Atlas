import 'package:flutter/material.dart';
import '../state/workspace_state.dart';

class FileExplorer extends StatefulWidget {
  const FileExplorer({super.key, required this.workspaceState});

  final WorkspaceState workspaceState;

  @override
  State<FileExplorer> createState() => _FileExplorerState();
}

class _FileExplorerState extends State<FileExplorer> {
  // Track which directories are expanded by their path
  final Set<String> _expandedDirs = {'lib'};

  @override
  Widget build(BuildContext context) {
    final tree = widget.workspaceState.engine.fileTree;

    return _PanelFrame(
      title: 'EXPLORER',
      actions: [
        IconButton(
          onPressed: () => _createEntry(context, isDirectory: false),
          icon: const Icon(Icons.note_add_outlined, size: 18),
          tooltip: 'New File',
        ),
        IconButton(
          onPressed: () => _createEntry(context, isDirectory: true),
          icon: const Icon(Icons.create_new_folder_outlined, size: 18),
          tooltip: 'New Folder',
        ),
      ],
      child: tree.isEmpty
          ? const Center(
              child: Text(
                'Connecting to engine...',
                style: TextStyle(color: Color(0xFF8E8E8E), fontSize: 13),
              ),
            )
          : ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: _buildTree(tree, 0, ''),
            ),
    );
  }

  Future<void> _createEntry(
    BuildContext context, {
    required bool isDirectory,
  }) async {
    final pathController = TextEditingController();
    final entryPath = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(isDirectory ? 'New Folder' : 'New File'),
        content: TextField(
          controller: pathController,
          autofocus: true,
          decoration: InputDecoration(
            labelText: 'Path',
            hintText: isDirectory ? 'lib/widgets' : 'lib/new_file.dart',
          ),
          onSubmitted: (value) => Navigator.pop(dialogContext, value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, pathController.text.trim()),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    pathController.dispose();

    if (entryPath == null || entryPath.isEmpty) return;
    if (isDirectory) {
      widget.workspaceState.createDirectory(entryPath);
    } else {
      widget.workspaceState.createFile(entryPath);
    }
  }

  List<Widget> _buildTree(List<dynamic> nodes, int depth, String parentPath) {
    List<Widget> widgets = [];
    for (final node in nodes) {
      final name = node['name'] as String;
      final isDir = node['type'] == 'dir';
      final fullPath = parentPath.isEmpty ? name : '$parentPath/$name';
      final padding = 16.0 + (depth * 12.0);
      final isExpanded = _expandedDirs.contains(fullPath);

      widgets.add(
        InkWell(
          onTap: () {
            if (isDir) {
              setState(() {
                if (isExpanded) {
                  _expandedDirs.remove(fullPath);
                } else {
                  _expandedDirs.add(fullPath);
                }
              });
            } else {
              widget.workspaceState.openFile(fullPath);
            }
          },
          child: Padding(
            padding: EdgeInsets.only(left: padding, right: 8, top: 6, bottom: 6),
            child: Row(
              children: [
                Icon(
                  isDir
                      ? (isExpanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_right)
                      : Icons.insert_drive_file_outlined,
                  size: 16,
                  color: isDir ? const Color(0xFFCCCCCC) : const Color(0xFF8E8E8E),
                ),
                const SizedBox(width: 6),
                Icon(
                  isDir ? Icons.folder_rounded : _fileIcon(name),
                  size: 16,
                  color: isDir ? const Color(0xFF3794FF) : _fileColor(name),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    name,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontSize: 13,
                      color: const Color(0xFFCCCCCC),
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
    if (name.endsWith('.yaml') || name.endsWith('.yml')) return Icons.settings;
    if (name.endsWith('.md')) return Icons.description_outlined;
    if (name.endsWith('.json')) return Icons.data_object;
    if (name.endsWith('.js')) return Icons.javascript;
    if (name.endsWith('.lock')) return Icons.lock_outlined;
    return Icons.insert_drive_file_outlined;
  }

  Color _fileColor(String name) {
    if (name.endsWith('.dart')) return const Color(0xFF519ABA);
    if (name.endsWith('.yaml') || name.endsWith('.yml')) return const Color(0xFFE37933);
    if (name.endsWith('.md')) return const Color(0xFF6A9955);
    if (name.endsWith('.json')) return const Color(0xFFCBCB41);
    if (name.endsWith('.js')) return const Color(0xFFCBCB41);
    return const Color(0xFF8E8E8E);
  }
}

class _PanelFrame extends StatelessWidget {
  const _PanelFrame({
    required this.title,
    required this.child,
    this.actions = const [],
  });

  final String title;
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
            height: 42,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Text(title, style: Theme.of(context).textTheme.labelMedium),
                  const Spacer(),
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
