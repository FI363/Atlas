const path = require('path');
const fs = require('fs');

/**
 * Manages targeted context assembly, system instructions, and token compaction.
 */
class ContextManager {
  constructor({ maxContextTokens = 32768 } = {}) {
    this.maxContextTokens = maxContextTokens;
  }

  /**
   * Builds the core provider-independent system prompt.
   *
   * @param {object} ideContext
   * @param {string} [ideContext.workspaceRoot]
   * @param {string} [ideContext.activeFile]
   * @param {string} [ideContext.activeSelection]
   * @param {Array<string>} [ideContext.openFiles]
   * @param {Array<object>} [ideContext.diagnostics]
   * @param {object} [ideContext.gitStatus]
   * @param {object} [settings]
   * @returns {string}
   */
  buildSystemPrompt(ideContext = {}, settings = {}) {
    const customPrompt = settings.aiSystemPrompt || '';

    const lines = [
      'You are Atlas, an expert autonomous coding agent embedded inside Atlas IDE.',
      'You have native tools that allow you to inspect and modify the user workspace directly.',
      '',
      '## Operational Guidelines',
      '1. **Inspect before modifying**: Use `read_file`, `list_directory`, and `search_code` to understand the codebase before making changes.',
      '2. **Real tool execution**: Never pretend or claim to have edited a file or run a command without executing the corresponding tool.',
      '3. **Targeted changes**: Make precise, clean code changes. Avoid unnecessary refactoring of unrelated code.',
      '4. **Verification**: After modifying code or fixing a bug, verify your work using `run_terminal_command` (e.g. running tests or analyzers).',
      '5. **Tool results are authoritative**: Base your subsequent reasoning on actual tool execution output.',
    ];

    if (customPrompt.trim()) {
      lines.push('', '## User Instructions', customPrompt.trim());
    }

    // IDE Context Block
    const contextSections = [];

    if (ideContext.workspaceRoot) {
      contextSections.push(`- **Workspace**: \`${ideContext.workspaceRoot}\` (${path.basename(ideContext.workspaceRoot)})`);
    }

    if (ideContext.activeFile) {
      contextSections.push(`- **Active File**: \`${ideContext.activeFile}\``);
      if (ideContext.activeSelection) {
        contextSections.push(`- **Active Editor Selection**:\n\`\`\`\n${ideContext.activeSelection}\n\`\`\``);
      }
    }

    if (Array.isArray(ideContext.openFiles) && ideContext.openFiles.length > 0) {
      contextSections.push(`- **Open Tabs**: ${ideContext.openFiles.map((f) => `\`${f}\``).join(', ')}`);
    }

    if (ideContext.gitStatus?.branch) {
      contextSections.push(`- **Git Branch**: \`${ideContext.gitStatus.branch}\``);
    }

    if (Array.isArray(ideContext.diagnostics) && ideContext.diagnostics.length > 0) {
      const errorList = ideContext.diagnostics
        .slice(0, 5)
        .map((d) => `  * ${d.file || ''}:${d.line || 1} - ${d.message || d}`)
        .join('\n');
      contextSections.push(`- **Current Workspace Diagnostics/Errors**:\n${errorList}`);
    }

    if (contextSections.length > 0) {
      lines.push('', '## Active IDE Context', ...contextSections);
    }

    return lines.join('\n');
  }

  /**
   * Approximate token count for text (rough 4 chars per token estimate).
   * @param {string} text
   * @returns {number}
   */
  estimateTokens(text) {
    if (!text || typeof text !== 'string') return 0;
    return Math.ceil(text.length / 4);
  }

  /**
   * Estimate token count of a full message history.
   * @param {Array<{role: string, content: string|null, tool_calls?: any[]}>} messages
   * @returns {number}
   */
  estimateConversationTokens(messages) {
    if (!Array.isArray(messages)) return 0;
    let tokens = 0;
    for (const msg of messages) {
      tokens += this.estimateTokens(msg.content || '');
      if (msg.tool_calls) {
        tokens += this.estimateTokens(JSON.stringify(msg.tool_calls));
      }
    }
    return tokens;
  }

  /**
   * Compacts conversation history if it approaches context limits.
   * Preserves system prompt, initial user goal, and recent turns while summarizing older tool outputs.
   *
   * @param {Array<object>} conversation
   * @param {number} [maxTokens]
   * @returns {Array<object>}
   */
  compactConversation(conversation, maxTokens = this.maxContextTokens) {
    if (!Array.isArray(conversation) || conversation.length <= 4) {
      return conversation;
    }

    const currentTokens = this.estimateConversationTokens(conversation);
    if (currentTokens <= maxTokens * 0.85) {
      return conversation;
    }

    // Keep system prompt (index 0) and original user request (index 1)
    const systemMsg = conversation[0]?.role === 'system' ? conversation[0] : null;
    const startIndex = systemMsg ? 1 : 0;
    const firstUserMsg = conversation[startIndex];

    // Keep recent 8 messages
    const recentTurns = conversation.slice(-8);

    // Truncate large tool outputs in middle messages
    const middleTurns = conversation.slice(startIndex + 1, -8).map((msg) => {
      if (msg.role === 'tool' && typeof msg.content === 'string' && msg.content.length > 300) {
        return {
          ...msg,
          content: `${msg.content.substring(0, 200)}\n... [output compacted to preserve context budget]`,
        };
      }
      return msg;
    });

    const result = [];
    if (systemMsg) result.push(systemMsg);
    if (firstUserMsg) result.push(firstUserMsg);
    result.push(...middleTurns);
    result.push(...recentTurns);

    return result;
  }
}

module.exports = {
  ContextManager,
};
