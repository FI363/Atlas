import 'package:flutter/material.dart';

import '../state/workspace_state.dart';

/// Right-side panel for interactive AI Agent chat stream and context-aware quick actions.
class AiPanel extends StatefulWidget {
  const AiPanel({super.key, required this.workspaceState});

  final WorkspaceState workspaceState;

  @override
  State<AiPanel> createState() => _AiPanelState();
}

class _AiPanelState extends State<AiPanel> {
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    widget.workspaceState.engine.addListener(_scrollToBottom);
  }

  @override
  void dispose() {
    widget.workspaceState.engine.removeListener(_scrollToBottom);
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      Future.delayed(const Duration(milliseconds: 100), () {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  void _sendPrompt(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    final activeFile = widget.workspaceState.activeFile;
    final contextCode = activeFile != null
        ? widget.workspaceState.contentForFile(activeFile)
        : null;

    widget.workspaceState.engine.sendAiPrompt(trimmed, contextCode: contextCode);
    _inputController.clear();
  }

  @override
  Widget build(BuildContext context) {
    final messages = widget.workspaceState.engine.aiMessages;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF252526),
        border: Border(left: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: Column(
        children: [
          // Header
          SizedBox(
            height: 38,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                children: [
                  const Icon(Icons.auto_awesome, size: 16, color: Color(0xFFC586C0)),
                  const SizedBox(width: 8),
                  const Text(
                    'ATLAS AI AGENT',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.8,
                      color: Color(0xFFCCCCCC),
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 16, color: Color(0xFF8E8E8E)),
                    onPressed: widget.workspaceState.toggleAiPanel,
                    splashRadius: 16,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),
          ),
          const Divider(height: 1),

          // Chat Message Stream
          Expanded(
            child: ListView.separated(
              controller: _scrollController,
              padding: const EdgeInsets.all(14),
              itemCount: messages.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final msg = messages[index];
                final isUser = msg['isUser'] as bool;
                final content = msg['content'] as String;

                return _buildMessageBubble(
                  isUser: isUser,
                  content: content,
                );
              },
            ),
          ),

          // Quick Action Chips (Context-Aware)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                _buildActionChip('Explain Code', () => _sendPrompt('Explain what this code does')),
                const SizedBox(width: 6),
                _buildActionChip('Find Bugs', () => _sendPrompt('Scan this file for potential bugs or null pointer issues')),
                const SizedBox(width: 6),
                _buildActionChip('Generate Tests', () => _sendPrompt('Generate unit tests for this code')),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // Input Box
          Padding(
            padding: const EdgeInsets.only(left: 12, right: 12, bottom: 12),
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF3C3C3C),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFF454545)),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _inputController,
                      maxLines: 4,
                      minLines: 1,
                      style: const TextStyle(fontSize: 13, color: Colors.white),
                      decoration: const InputDecoration(
                        hintText: 'Ask AI Agent (context auto-included)...',
                        hintStyle: TextStyle(color: Color(0xFF8E8E8E), fontSize: 12),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                      onSubmitted: _sendPrompt,
                    ),
                  ),
                  const SizedBox(width: 6),
                  InkWell(
                    onTap: () => _sendPrompt(_inputController.text),
                    child: const Padding(
                      padding: EdgeInsets.all(4.0),
                      child: Icon(Icons.send_rounded, size: 16, color: Color(0xFF007ACC)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble({required bool isUser, required String content}) {
    return Column(
      crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!isUser) const Icon(Icons.auto_awesome, size: 13, color: Color(0xFFC586C0)),
            if (!isUser) const SizedBox(width: 6),
            Text(
              isUser ? 'You' : 'Atlas Agent',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: Color(0xFFCCCCCC)),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: isUser ? const Color(0xFF2D2D30) : const Color(0xFF1E1E1E),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: const Color(0xFF3C3C3C)),
          ),
          child: SelectableText(
            content,
            style: const TextStyle(fontSize: 12.5, color: Color(0xFFE7E7E7), height: 1.4),
          ),
        ),
      ],
    );
  }

  Widget _buildActionChip(String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: const Color(0xFF2D2D2D),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF454545)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.bolt, size: 12, color: Color(0xFFC586C0)),
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(fontSize: 11, color: Color(0xFFCCCCCC)),
            ),
          ],
        ),
      ),
    );
  }
}
