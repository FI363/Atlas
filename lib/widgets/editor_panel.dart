import 'package:flutter/material.dart';

import '../state/workspace_state.dart';

/// Main editor surface supporting tabs and syntax-highlighted code.
class EditorPanel extends StatelessWidget {
  const EditorPanel({super.key, required this.workspaceState});

  final WorkspaceState workspaceState;

  @override
  Widget build(BuildContext context) {
    if (workspaceState.openFiles.isEmpty) {
      return Container(
        color: const Color(0xFF1E1E1E),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.code_rounded, size: 42, color: Color(0xFF8E8E8E)),
              const SizedBox(height: 12),
              Text('Atlas Editor', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              Text('Open a file to start editing.', style: Theme.of(context).textTheme.bodySmall),
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
          // Tab Bar
          SizedBox(
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
                    decoration: BoxDecoration(
                      color: isActive ? const Color(0xFF1E1E1E) : const Color(0xFF2D2D2D),
                      border: Border(
                        top: BorderSide(
                          color: isActive ? const Color(0xFF3794FF) : Colors.transparent,
                          width: 2,
                        ),
                        right: BorderSide(color: Theme.of(context).dividerColor),
                      ),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          file,
                          style: TextStyle(
                            color: isActive ? Colors.white : const Color(0xFF9D9D9D),
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: () => workspaceState.closeFile(file),
                          child: Icon(
                            Icons.close_rounded,
                            size: 14,
                            color: isActive ? const Color(0xFFCCCCCC) : const Color(0xFF8E8E8E),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          
          // Code Area
          Expanded(
            child: _buildCodeArea(),
          ),
        ],
      ),
    );
  }

  Widget _buildCodeArea() {
    final activeFile = workspaceState.activeFile;
    if (activeFile == null) {
      return const SizedBox.shrink();
    }

    final content = workspaceState.engine.getFileContent(activeFile);

    if (content == null) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
            SizedBox(height: 12),
            Text('Loading file...', style: TextStyle(color: Color(0xFF8E8E8E), fontSize: 13)),
          ],
        ),
      );
    }

    final lines = content.split('\n');

    return SingleChildScrollView(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Line Numbers
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: List.generate(lines.length, (i) => SizedBox(
                  height: 20,
                  child: Text(
                    '${i + 1}',
                    style: const TextStyle(
                      color: Color(0xFF858585),
                      fontFamily: 'Consolas',
                      fontSize: 14,
                    ),
                  ),
                )),
              ),
              const SizedBox(width: 16),
              // Code Content
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: lines.map((line) => SizedBox(
                  height: 20,
                  child: Text(
                    line,
                    style: const TextStyle(
                      color: Color(0xFFD4D4D4),
                      fontFamily: 'Consolas',
                      fontSize: 14,
                    ),
                  ),
                )).toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
