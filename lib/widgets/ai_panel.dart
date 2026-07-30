import 'package:flutter/material.dart';

import '../state/workspace_state.dart';

/// Right-side panel for Atlas AI chat interactions.
class AiPanel extends StatelessWidget {
  const AiPanel({super.key, required this.workspaceState});

  final WorkspaceState workspaceState;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF252526),
        border: Border(left: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: Column(
        children: [
          // Header
          SizedBox(
            height: 42,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  const Icon(Icons.auto_awesome, size: 16, color: Color(0xFFC586C0)),
                  const SizedBox(width: 8),
                  Text('ATLAS AI', style: Theme.of(context).textTheme.labelMedium),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 16, color: Color(0xFF8E8E8E)),
                    onPressed: workspaceState.toggleAiPanel,
                    splashRadius: 20,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),
          ),
          const Divider(height: 1),
          
          // Chat Stream Area
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildMessageBubble(
                  isUser: true,
                  content: 'How do I center a div in CSS?',
                  context: context,
                ),
                const SizedBox(height: 16),
                _buildMessageBubble(
                  isUser: false,
                  content: 'To center a div in CSS, the most modern approach is using Flexbox. Here is an example:\n\n```css\n.container {\n  display: flex;\n  justify-content: center;\n  align-items: center;\n}\n```',
                  context: context,
                ),
              ],
            ),
          ),
          
          // Quick Action Chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                _buildChip('Explain Code'),
                const SizedBox(width: 8),
                _buildChip('Find Bugs'),
                const SizedBox(width: 8),
                _buildChip('Generate Tests'),
              ],
            ),
          ),
          const SizedBox(height: 12),
          
          // Input Box
          Padding(
            padding: const EdgeInsets.only(left: 12, right: 12, bottom: 12),
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF3C3C3C),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF454545)),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Expanded(
                    child: TextField(
                      maxLines: 5,
                      minLines: 1,
                      style: TextStyle(fontSize: 13, color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'Ask Atlas AI or type / to run a command...',
                        hintStyle: TextStyle(color: Color(0xFF8E8E8E)),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(Icons.send_rounded, size: 18, color: Theme.of(context).colorScheme.primary),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble({required bool isUser, required String content, required BuildContext context}) {
    return Column(
      crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!isUser) const Icon(Icons.auto_awesome, size: 14, color: Color(0xFFC586C0)),
            if (!isUser) const SizedBox(width: 6),
            Text(
              isUser ? 'You' : 'Atlas',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Color(0xFFCCCCCC)),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isUser ? const Color(0xFF2D2D30) : const Color(0xFF1E1E1E),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFF3C3C3C)),
          ),
          child: Text(
            content,
            style: const TextStyle(fontSize: 13, color: Color(0xFFE7E7E7)),
          ),
        ),
      ],
    );
  }

  Widget _buildChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF2D2D2D),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF3C3C3C)),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 11, color: Color(0xFFCCCCCC)),
      ),
    );
  }
}

