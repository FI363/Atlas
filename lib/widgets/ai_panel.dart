import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../state/agent_state.dart';
import '../state/workspace_state.dart';
import 'diff_view.dart';

/// Right-side panel for interactive AI Agent chat stream, file/image attachments,
/// live tool execution step cards, permission approval requests, and diff reviews.
class AiPanel extends StatefulWidget {
  const AiPanel({super.key, required this.workspaceState});

  final WorkspaceState workspaceState;

  @override
  State<AiPanel> createState() => _AiPanelState();
}

class _AiPanelState extends State<AiPanel> {
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();
  final _inputFocusNode = FocusNode();
  final _keyboardFocusNode = FocusNode();
  final List<Map<String, dynamic>> _attachments = [];
  String _statusText = '';
  bool get _canSend =>
      !widget.workspaceState.engine.isAiThinking &&
      !widget.workspaceState.engine.agentState.isAgentRunning;

  @override
  void initState() {
    super.initState();
    widget.workspaceState.engine.addListener(_onEngineChanged);
    widget.workspaceState.engine.agentState.addListener(_onAgentStateChanged);
  }

  @override
  void dispose() {
    widget.workspaceState.engine.removeListener(_onEngineChanged);
    widget.workspaceState.engine.agentState.removeListener(_onAgentStateChanged);
    _inputController.dispose();
    _scrollController.dispose();
    _inputFocusNode.dispose();
    _keyboardFocusNode.dispose();
    super.dispose();
  }

  void _onEngineChanged() {
    final engine = widget.workspaceState.engine;
    final picked = engine.takePendingAttachments();
    final clipboard = engine.takeClipboardPasteResult();
    if (picked.isNotEmpty) {
      setState(() {
        _attachments.addAll(picked);
        _statusText = 'Attached ${_attachments.length} item${_attachments.length == 1 ? '' : 's'}';
      });
    }
    if (clipboard != null) _handleClipboardOrAttachment(clipboard);
    _scrollToBottom();
  }

  void _onAgentStateChanged() {
    if (mounted) setState(() {});
    _scrollToBottom();
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

    // Build full workspace context for the AI Agent
    final openFilesContext = <Map<String, String>>[];
    for (final filePath in widget.workspaceState.openFiles) {
      final content = widget.workspaceState.contentForFile(filePath);
      if (content != null) {
        openFilesContext.add({'path': filePath, 'content': content});
      }
    }

    final workspaceContext = <String, dynamic>{
      'projectName': widget.workspaceState.engine.projectName,
      'cwd': widget.workspaceState.engine.cwd,
      'activeFile': activeFile ?? '',
      'openFiles': openFilesContext,
      'fileTree': widget.workspaceState.engine.fileTree,
    };

    final useAgent = widget.workspaceState.settings.useAgentMode;

    widget.workspaceState.engine.sendAiPrompt(
      trimmed,
      workspaceContext: workspaceContext,
      settingsPayload: widget.workspaceState.settings.toMap(),
      attachments: List<Map<String, dynamic>>.from(_attachments),
      useAgentMode: useAgent,
    );

    _inputController.clear();
    setState(() {
      _attachments.clear();
      _statusText = useAgent ? 'Agent Task Started' : 'Sent to AI';
    });
  }

  void _handleInputKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return;
    if (event.logicalKey != LogicalKeyboardKey.enter) return;

    final isShiftPressed = HardwareKeyboard.instance.isShiftPressed;
    if (isShiftPressed) return;

    _sendPrompt(_inputController.text);
  }

  void _setStatus(String text) {
    if (!mounted) return;
    setState(() => _statusText = text);
  }

  void _handleClipboardOrAttachment(dynamic data) {
    if (data is Map && data['kind'] == 'text' && data['text'] is String) {
      final text = data['text'] as String;
      final selection = _inputController.selection;
      final value = _inputController.value;
      final start = selection.start >= 0 ? selection.start : value.text.length;
      final end = selection.end >= 0 ? selection.end : value.text.length;
      final nextText = value.text.replaceRange(start, end, text);
      _inputController.value = value.copyWith(
        text: nextText,
        selection: TextSelection.collapsed(offset: start + text.length),
      );
      _setStatus('Pasted text from clipboard');
      return;
    }

    if (data is Map && data['kind'] == 'attachment' && data['attachment'] is Map) {
      setState(() {
        _attachments.add(Map<String, dynamic>.from(data['attachment'] as Map));
        _statusText = 'Attached ${_attachments.length} item${_attachments.length == 1 ? '' : 's'}';
      });
    }
  }

  void _removeAttachmentAt(int index) {
    setState(() {
      _attachments.removeAt(index);
      _statusText = _attachments.isEmpty ? '' : 'Attached ${_attachments.length} item${_attachments.length == 1 ? '' : 's'}';
    });
  }

  void _applyCodeToWorkspace(String code, String? targetPath) {
    final pathToApply = targetPath ?? widget.workspaceState.activeFile;
    if (pathToApply == null || pathToApply.isEmpty) {
      _setStatus('No active file open to apply code');
      return;
    }

    widget.workspaceState.openFile(pathToApply);
    widget.workspaceState.updateDraft(pathToApply, code);
    widget.workspaceState.saveFile(pathToApply, code);
    _setStatus('Applied code to $pathToApply');
  }

  void _runCommandInTerminal(String command) {
    widget.workspaceState.runProject(command.trim());
    _setStatus('Running terminal command');
  }

  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    _setStatus('Copied to clipboard');
  }

  @override
  Widget build(BuildContext context) {
    final messages = widget.workspaceState.engine.aiMessages;
    final agentState = widget.workspaceState.engine.agentState;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF252526),
        border: Border(left: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: Column(
        children: [
          // Header Bar with Mode Switch
          SizedBox(
            height: 42,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  const Icon(Icons.auto_awesome, size: 16, color: Color(0xFFC586C0)),
                  const SizedBox(width: 8),
                  const Text(
                    'ATLAS AGENT',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.8,
                      color: Color(0xFFCCCCCC),
                    ),
                  ),
                  const Spacer(),

                  // Toggle Agent Mode
                  Tooltip(
                    message: widget.workspaceState.settings.useAgentMode
                        ? 'Agent Mode (MCP Tool Execution Active)'
                        : 'Simple Chat Mode',
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.workspaceState.settings.useAgentMode ? 'AGENT' : 'CHAT',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: widget.workspaceState.settings.useAgentMode
                                ? const Color(0xFF4FC3F7)
                                : const Color(0xFF8E8E8E),
                          ),
                        ),
                        Switch(
                          value: widget.workspaceState.settings.useAgentMode,
                          onChanged: (val) {
                            setState(() {
                              widget.workspaceState.settings.useAgentMode = val;
                              widget.workspaceState.applySettings();
                            });
                          },
                          activeThumbColor: const Color(0xFF007ACC),
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ],
                    ),
                  ),

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

          // Stream & Active Agent Operations Body
          Expanded(
            child: ListView(
              controller: _scrollController,
              padding: const EdgeInsets.all(14),
              children: [
                for (int i = 0; i < messages.length; i++) ...[
                  _buildMessageBubble(
                    isUser: messages[i]['isUser'] == true,
                    content: messages[i]['content']?.toString() ?? '',
                  ),
                  const SizedBox(height: 14),
                ],

                // Live Agent Tools & Steps View
                if (agentState.isAgentRunning || agentState.toolCalls.isNotEmpty) ...[
                  _buildAgentExecutionCard(agentState),
                  const SizedBox(height: 14),
                ],

                // Live Approval Request Card
                if (agentState.pendingApproval != null) ...[
                  _buildApprovalCard(agentState.pendingApproval!),
                  const SizedBox(height: 14),
                ],

                // Live Diff Proposal View
                if (agentState.pendingDiff != null) ...[
                  DiffViewCard(
                    filePath: agentState.pendingDiff!['path'] as String? ?? '',
                    diffText: agentState.pendingDiff!['diff'] as String? ?? '',
                    onAccept: () => widget.workspaceState.engine.respondToDiff(true),
                    onReject: () => widget.workspaceState.engine.respondToDiff(false),
                  ),
                  const SizedBox(height: 14),
                ],

                // General thinking indicator
                if (widget.workspaceState.engine.isAiThinking && !agentState.isAgentRunning)
                  _buildThinkingBubble(),
              ],
            ),
          ),

          if (_statusText.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              color: const Color(0xFF1E1E1E),
              child: Text(
                _statusText,
                style: const TextStyle(fontSize: 11.5, color: Color(0xFF9D9D9D)),
              ),
            ),

          if (_attachments.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (int i = 0; i < _attachments.length; i++)
                    _AttachmentChip(
                      attachment: _attachments[i],
                      onRemove: () => _removeAttachmentAt(i),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 8),

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
                  IconButton(
                    tooltip: 'Attach files',
                    onPressed: () {
                      widget.workspaceState.engine.pickAttachments();
                      _setStatus('Selecting files...');
                    },
                    icon: const Icon(Icons.add_circle_outline, size: 18, color: Color(0xFF9D9D9D)),
                    splashRadius: 16,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                  Expanded(
                    child: Focus(
                      focusNode: _keyboardFocusNode,
                      onKeyEvent: (node, event) {
                        if (event is KeyDownEvent &&
                            event.logicalKey == LogicalKeyboardKey.keyV &&
                            HardwareKeyboard.instance.isControlPressed) {
                          widget.workspaceState.engine.pasteClipboardAttachment();
                          _setStatus('Reading clipboard...');
                          return KeyEventResult.handled;
                        }
                        _handleInputKeyEvent(event);
                        return KeyEventResult.ignored;
                      },
                      child: TextField(
                        controller: _inputController,
                        focusNode: _inputFocusNode,
                        maxLines: 4,
                        minLines: 1,
                        style: const TextStyle(fontSize: 13, color: Colors.white),
                        decoration: InputDecoration(
                          hintText: widget.workspaceState.settings.useAgentMode
                              ? 'Assign Atlas Agent a task...'
                              : 'Ask AI Agent...',
                          hintStyle: const TextStyle(color: Color(0xFF8E8E8E), fontSize: 12),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                        onTapOutside: (_) => _inputFocusNode.unfocus(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),

                  if (agentState.isAgentRunning)
                    IconButton(
                      tooltip: 'Stop Agent Execution',
                      onPressed: () => widget.workspaceState.engine.cancelAgent(),
                      icon: const Icon(Icons.stop_circle_outlined, size: 20, color: Color(0xFFF85149)),
                      splashRadius: 16,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    )
                  else
                    InkWell(
                      onTap: _canSend
                          ? () {
                              _sendPrompt(_inputController.text);
                              _inputFocusNode.requestFocus();
                            }
                          : null,
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

  Widget _buildAgentExecutionCard(AgentState agentState) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFF007ACC)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (agentState.isAgentRunning)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF4FC3F7)),
                  ),
                )
              else
                const Icon(Icons.check_circle_outline, size: 16, color: Color(0xFF7EE787)),
              const SizedBox(width: 8),
              Text(
                agentState.isAgentRunning ? 'Atlas Agent Execution' : 'Agent Steps Executed',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const Spacer(),
              Text(
                'Step ${agentState.currentIteration}',
                style: const TextStyle(fontSize: 11, color: Color(0xFF8E8E8E)),
              ),
            ],
          ),
          if (agentState.currentStatus.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              agentState.currentStatus,
              style: const TextStyle(fontSize: 11.5, color: Color(0xFFCCCCCC)),
            ),
          ],
          if (agentState.toolCalls.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Divider(height: 1, color: Color(0xFF333333)),
            const SizedBox(height: 8),
            for (final tool in agentState.toolCalls) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Icon(
                      tool['status'] == 'completed'
                          ? Icons.check
                          : tool['status'] == 'denied'
                              ? Icons.close
                              : Icons.sync,
                      size: 13,
                      color: tool['status'] == 'completed'
                          ? const Color(0xFF7EE787)
                          : tool['status'] == 'denied'
                              ? const Color(0xFFF85149)
                              : const Color(0xFF4FC3F7),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      tool['toolName'] as String? ?? 'tool',
                      style: const TextStyle(
                        fontFamily: 'Consolas',
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF4FC3F7),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _formatToolArgs(tool['args']),
                        style: const TextStyle(fontSize: 10.5, color: Color(0xFF8E8E8E)),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildApprovalCard(Map<String, dynamic> approvalInfo) {
    final requestId = approvalInfo['requestId'] as String? ?? '';
    final toolName = approvalInfo['toolName'] as String? ?? 'Operation';
    final category = approvalInfo['category'] as String? ?? 'EXECUTE';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF2D2013),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFFD19A66)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.shield_outlined, size: 16, color: Color(0xFFD19A66)),
              const SizedBox(width: 8),
              Text(
                'Permission Required ($category)',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFFD19A66)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Atlas wants permission to execute tool: "$toolName"',
            style: const TextStyle(fontSize: 12, color: Colors.white),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              OutlinedButton(
                onPressed: () => widget.workspaceState.engine.respondToApproval(requestId, false),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFF85149),
                  side: const BorderSide(color: Color(0xFFF85149)),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  minimumSize: Size.zero,
                ),
                child: const Text('Deny', style: TextStyle(fontSize: 11)),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: () => widget.workspaceState.engine.respondToApproval(requestId, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF238636),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  minimumSize: Size.zero,
                ),
                child: const Text('Allow Action', style: TextStyle(fontSize: 11)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatToolArgs(dynamic args) {
    if (args is Map) {
      if (args.containsKey('path')) return args['path'].toString();
      if (args.containsKey('query')) return 'query: "${args['query']}"';
      if (args.containsKey('command')) return 'cmd: "${args['command']}"';
    }
    return args ? args.toString() : '';
  }

  Widget _buildMessageBubble({required bool isUser, required String content}) {
    final segments = _parseContent(content);

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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final seg in segments)
                if (seg.isCode)
                  _buildCodeBlock(seg)
                else if (seg.text.trim().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: SelectableText(
                      seg.text.trim(),
                      style: const TextStyle(fontSize: 12.5, color: Color(0xFFE7E7E7), height: 1.4),
                    ),
                  ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCodeBlock(_Segment seg) {
    final lang = seg.language ?? 'code';
    final targetPath = seg.filePath ?? widget.workspaceState.activeFile;
    final isTerminalCmd = ['bash', 'sh', 'powershell', 'cmd', 'terminal'].contains(lang.toLowerCase());

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF181818),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0x80007ACC)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: const BoxDecoration(
              color: Color(0xFF2D2D2D),
              borderRadius: BorderRadius.vertical(top: Radius.circular(5)),
            ),
            child: Row(
              children: [
                Icon(
                  isTerminalCmd ? Icons.terminal : Icons.code,
                  size: 14,
                  color: const Color(0xFF4FC3F7),
                ),
                const SizedBox(width: 6),
                Text(
                  lang.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF4FC3F7),
                  ),
                ),
                if (targetPath != null) ...[
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      '($targetPath)',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11, color: Color(0xFF8E8E8E)),
                    ),
                  ),
                ],
                const Spacer(),
                if (isTerminalCmd)
                  InkWell(
                    onTap: () => _runCommandInTerminal(seg.text),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF238636),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(
                        children: const [
                          Icon(Icons.play_arrow, size: 12, color: Colors.white),
                          SizedBox(width: 2),
                          Text('Run', style: TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  )
                else
                  InkWell(
                    onTap: () => _applyCodeToWorkspace(seg.text, seg.filePath),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0E639C),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(
                        children: const [
                          Icon(Icons.bolt, size: 12, color: Colors.white),
                          SizedBox(width: 2),
                          Text('Apply to Code', style: TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(width: 6),
                InkWell(
                  onTap: () => _copyToClipboard(seg.text),
                  child: const Icon(Icons.copy_rounded, size: 14, color: Color(0xFFCCCCCC)),
                ),
              ],
            ),
          ),
          // Code Body
          Padding(
            padding: const EdgeInsets.all(10),
            child: SelectableText(
              seg.text.trim(),
              style: const TextStyle(
                fontFamily: 'Consolas',
                fontSize: 12,
                color: Color(0xFFDCDCAA),
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildThinkingBubble() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.auto_awesome, size: 13, color: Color(0xFFC586C0)),
            SizedBox(width: 6),
            Text(
              'Atlas Agent',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: Color(0xFFCCCCCC)),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E1E),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: const Color(0xFF3C3C3C)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: const [
              SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFC586C0)),
                ),
              ),
              SizedBox(width: 10),
              Text(
                'Thinking & Analyzing Code...',
                style: TextStyle(fontSize: 12.5, color: Color(0xFF8E8E8E)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  List<_Segment> _parseContent(String text) {
    final segments = <_Segment>[];
    final parts = text.split('```');

    for (int i = 0; i < parts.length; i++) {
      final part = parts[i];
      if (i % 2 == 1) {
        // Inside code block
        final lines = part.split('\n');
        final header = lines.first.trim();
        final body = lines.sublist(1).join('\n');

        String? lang;
        String? path;

        if (header.contains(':')) {
          final headerParts = header.split(':');
          lang = headerParts[0].trim();
          path = headerParts.sublist(1).join(':').trim();
        } else if (header.isNotEmpty) {
          lang = header;
        }

        segments.add(_Segment(
          isCode: true,
          text: body,
          language: lang,
          filePath: path,
        ));
      } else {
        if (part.isNotEmpty) {
          segments.add(_Segment(isCode: false, text: part));
        }
      }
    }
    return segments;
  }
}

class _Segment {
  final bool isCode;
  final String text;
  final String? language;
  final String? filePath;

  _Segment({
    required this.isCode,
    required this.text,
    this.language,
    this.filePath,
  });
}

class _AttachmentChip extends StatelessWidget {
  const _AttachmentChip({required this.attachment, required this.onRemove});

  final Map<String, dynamic> attachment;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final isImage = attachment['kind'] == 'image' || attachment['type'] == 'image';
    final name = (attachment['name'] as String?) ?? 'attachment';
    return Chip(
      avatar: Icon(isImage ? Icons.image_outlined : Icons.insert_drive_file_outlined,
          size: 15, color: const Color(0xFF9CDCFE)),
      label: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 180),
        child: Text(name, overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11, color: Color(0xFFD4D4D4))),
      ),
      deleteIcon: const Icon(Icons.close, size: 14, color: Color(0xFF9D9D9D)),
      onDeleted: onRemove,
      backgroundColor: const Color(0xFF2D2D30),
      side: const BorderSide(color: Color(0xFF454545)),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
    );
  }
}
