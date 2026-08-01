import 'package:flutter/material.dart';

import '../state/workspace_state.dart';

/// Workspace text search sidebar panel.
class SearchPanel extends StatefulWidget {
  const SearchPanel({super.key, required this.workspaceState});

  final WorkspaceState workspaceState;

  @override
  State<SearchPanel> createState() => _SearchPanelState();
}

class _SearchPanelState extends State<SearchPanel> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _performSearch(String query) {
    if (query.trim().isNotEmpty) {
      widget.workspaceState.engine.searchWorkspace(query.trim());
    }
  }

  @override
  Widget build(BuildContext context) {
    final results = widget.workspaceState.engine.searchResults;
    final query = widget.workspaceState.engine.searchQuery;

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
                const Icon(Icons.search_rounded, size: 16, color: Color(0xFF9D9D9D)),
                const SizedBox(width: 8),
                const Text(
                  'SEARCH',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                    color: Color(0xFFCCCCCC),
                  ),
                ),
                const Spacer(),
                Text(
                  '${results.length} results',
                  style: const TextStyle(fontSize: 11, color: Color(0xFF666666)),
                ),
              ],
            ),
          ),

          // Search Input
          Padding(
            padding: const EdgeInsets.all(10),
            child: TextField(
              controller: _searchController,
              style: const TextStyle(fontSize: 12.5, color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Search files (e.g. class, function)...',
                hintStyle: const TextStyle(color: Color(0xFF666666), fontSize: 12),
                prefixIcon: const Icon(Icons.search_rounded, size: 16, color: Color(0xFF8E8E8E)),
                filled: true,
                fillColor: const Color(0xFF3C3C3C),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                isDense: true,
              ),
              onSubmitted: _performSearch,
            ),
          ),

          const Divider(height: 1, color: Color(0xFF3C3C3C)),

          // Results List
          Expanded(
            child: query.isEmpty
                ? const Center(
                    child: Text('Type a query and press Enter', style: TextStyle(color: Color(0xFF666666), fontSize: 12)),
                  )
                : results.isEmpty
                    ? const Center(
                        child: Text('No matching results found', style: TextStyle(color: Color(0xFF666666), fontSize: 12)),
                      )
                    : ListView.builder(
                        itemCount: results.length,
                        itemBuilder: (context, index) {
                          final item = results[index];
                          final path = item['path'] as String;
                          final line = item['line'] as int;
                          final snippet = item['snippet'] as String;

                          return InkWell(
                            onTap: () => widget.workspaceState.openFile(path),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: const BoxDecoration(
                                border: Border(bottom: BorderSide(color: Color(0xFF2D2D2D))),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(Icons.insert_drive_file_outlined, size: 14, color: Color(0xFF3794FF)),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          path,
                                          style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: Color(0xFFCCCCCC),
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      Text(
                                        'Line $line',
                                        style: const TextStyle(fontSize: 10, color: Color(0xFF007ACC), fontFamily: 'Consolas'),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    snippet,
                                    style: const TextStyle(
                                      fontSize: 11.5,
                                      color: Color(0xFF858585),
                                      fontFamily: 'Consolas',
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
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
}
