import 'package:flutter/material.dart';

import '../state/workspace_state.dart';

/// Workspace Source Control / Git panel with file status and commit action.
class GitPanel extends StatefulWidget {
  const GitPanel({super.key, required this.workspaceState});

  final WorkspaceState workspaceState;

  @override
  State<GitPanel> createState() => _GitPanelState();
}

class _GitPanelState extends State<GitPanel> {
  final _commitController = TextEditingController();

  @override
  void initState() {
    super.initState();
    widget.workspaceState.engine.fetchGitStatus();
  }

  @override
  void dispose() {
    _commitController.dispose();
    super.dispose();
  }

  void _commit() {
    final msg = _commitController.text.trim();
    if (msg.isNotEmpty) {
      widget.workspaceState.engine.commitGit(msg);
      _commitController.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final branch = widget.workspaceState.engine.gitBranch;
    final files = widget.workspaceState.engine.gitFiles;

    return Container(
      color: const Color(0xFF252526),
      child: Column(
        children: [
          // Header
          Container(
            height: 38,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0xFF3C3C3C))),
            ),
            child: Row(
              children: [
                const Icon(Icons.account_tree_outlined, size: 16, color: Color(0xFF9D9D9D)),
                const SizedBox(width: 8),
                const Text(
                  'SOURCE CONTROL',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                    color: Color(0xFFCCCCCC),
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.refresh_rounded, size: 16, color: Color(0xFF8E8E8E)),
                  onPressed: widget.workspaceState.engine.fetchGitStatus,
                  tooltip: 'Refresh Git Status',
                  splashRadius: 16,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
                const SizedBox(width: 10),
                IconButton(
                  icon: const Icon(Icons.download_rounded, size: 16, color: Color(0xFF8E8E8E)),
                  onPressed: () => widget.workspaceState.engine.pullGithub(branch),
                  tooltip: 'Pull from GitHub',
                  splashRadius: 16,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
                const SizedBox(width: 10),
                IconButton(
                  icon: const Icon(Icons.upload_rounded, size: 16, color: Color(0xFF8E8E8E)),
                  onPressed: () => widget.workspaceState.engine.pushGithub(branch),
                  tooltip: 'Push to GitHub',
                  splashRadius: 16,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),

          // Branch Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            color: const Color(0xFF1E1E1E),
            child: Row(
              children: [
                const Icon(Icons.alt_route_outlined, size: 14, color: Color(0xFF4EC9B0)),
                const SizedBox(width: 6),
                Text(
                  'Branch: $branch',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF4EC9B0)),
                ),
              ],
            ),
          ),

          // Commit Box
          Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _commitController,
                  style: const TextStyle(fontSize: 12.5, color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Message (Ctrl+Enter to commit)',
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
                  onSubmitted: (_) => _commit(),
                ),
                const SizedBox(height: 8),
                ElevatedButton.icon(
                  onPressed: _commit,
                  icon: const Icon(Icons.check_rounded, size: 14),
                  label: const Text('Commit Changes', style: TextStyle(fontSize: 12)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF007ACC),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => _createGithubRepository(context),
                  icon: const Icon(Icons.cloud_upload_outlined, size: 14),
                  label: const Text('Publish to GitHub', style: TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFCCCCCC),
                    side: const BorderSide(color: Color(0xFF3C3C3C)),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                  ),
                ),
              ],
            ),
          ),

          const Divider(height: 1, color: Color(0xFF3C3C3C)),

          // Changed Files List
          Expanded(
            child: files.isEmpty
                ? const Center(
                    child: Text('No working tree changes', style: TextStyle(color: Color(0xFF666666), fontSize: 12)),
                  )
                : ListView.builder(
                    itemCount: files.length,
                    itemBuilder: (context, index) {
                      final item = files[index];
                      final status = item['status'] as String;
                      final filePath = item['path'] as String;

                      Color statusColor = const Color(0xFFDCDCAA);
                      if (status == 'M') statusColor = const Color(0xFFE5C07B);
                      if (status == 'A' || status == '??') statusColor = const Color(0xFF4CAF50);
                      if (status == 'D') statusColor = const Color(0xFFF44336);

                      return InkWell(
                        onTap: () => widget.workspaceState.openFile(filePath),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          decoration: const BoxDecoration(
                            border: Border(bottom: BorderSide(color: Color(0xFF2D2D2D))),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                decoration: BoxDecoration(
                                  color: statusColor.withAlpha(50),
                                  borderRadius: BorderRadius.circular(3),
                                ),
                                child: Text(
                                  status.isEmpty ? 'M' : status,
                                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: statusColor),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  filePath,
                                  style: const TextStyle(fontSize: 12, color: Color(0xFFCCCCCC)),
                                  overflow: TextOverflow.ellipsis,
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
    );
  }

  Future<void> _createGithubRepository(BuildContext context) async {
    final controller = TextEditingController(text: widget.workspaceState.projectName);
    final repositoryName = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF252526),
        title: const Text('Publish to GitHub', style: TextStyle(color: Colors.white, fontSize: 16)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            labelText: 'Repository name',
            labelStyle: TextStyle(color: Color(0xFF9D9D9D)),
          ),
          onSubmitted: (value) => Navigator.pop(dialogContext, value.trim()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('Create private repository'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (repositoryName == null || repositoryName.isEmpty) return;

    widget.workspaceState.engine.createGithubRepository(
      name: repositoryName,
      isPrivate: true,
      token: widget.workspaceState.settings.githubToken,
    );
  }
}
