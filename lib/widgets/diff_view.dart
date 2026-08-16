import 'package:flutter/material.dart';

/// Interactive Flutter diff review widget for Atlas Agent.
/// Renders unified diffs with line additions (+ green) and deletions (- red).
class DiffViewCard extends StatelessWidget {
  const DiffViewCard({
    super.key,
    required this.filePath,
    required this.diffText,
    required this.onAccept,
    required this.onReject,
  });

  final String filePath;
  final String diffText;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final lines = diffText.split('\n');

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFF007ACC)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: const BoxDecoration(
              color: Color(0xFF2D2D2D),
              borderRadius: BorderRadius.vertical(top: Radius.circular(5)),
            ),
            child: Row(
              children: [
                const Icon(Icons.difference_outlined, size: 16, color: Color(0xFF4FC3F7)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Proposed Diff: $filePath',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: onAccept,
                  icon: const Icon(Icons.check, size: 14),
                  label: const Text('Accept', style: TextStyle(fontSize: 11)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF238636),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
                const SizedBox(width: 6),
                OutlinedButton.icon(
                  onPressed: onReject,
                  icon: const Icon(Icons.close, size: 14),
                  label: const Text('Reject', style: TextStyle(fontSize: 11)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFF85149),
                    side: const BorderSide(color: Color(0xFFF85149)),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ],
            ),
          ),

          // Diff Content Body
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 250),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final line in lines) _buildDiffLine(line),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDiffLine(String line) {
    Color bg = Colors.transparent;
    Color fg = const Color(0xFFCCCCCC);

    if (line.startsWith('+') && !line.startsWith('+++')) {
      bg = const Color(0x332EA043);
      fg = const Color(0xFF7EE787);
    } else if (line.startsWith('-') && !line.startsWith('---')) {
      bg = const Color(0x33DA3633);
      fg = const Color(0xFFFFA198);
    } else if (line.startsWith('@@')) {
      fg = const Color(0xFFD2A8FF);
    }

    return Container(
      color: bg,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      child: Text(
        line,
        style: TextStyle(
          fontFamily: 'Consolas',
          fontSize: 11.5,
          color: fg,
        ),
      ),
    );
  }
}
