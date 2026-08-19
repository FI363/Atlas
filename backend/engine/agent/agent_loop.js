const { buildAgentSystemPrompt, selectRelevantFiles } = require('./context_builder');
const { generateUnifiedDiff } = require('./diff_engine');
const { compactConversation } = require('./context_manager');
const { CancellationToken } = require('./cancellation_token');

class AgentLoop {
  constructor({ workspaceRoot, permissionManager, toolRegistry, callbacks, settings = {}, conversation }) {
    this.workspaceRoot = workspaceRoot;
    this.permissionManager = permissionManager;
    this.toolRegistry = toolRegistry;
    this.callbacks = callbacks || {};
    this.settings = settings;
    this.maxIterations = settings.agentMaxIterations || 25;
    this.cancellation = new CancellationToken();
    // A transcript belongs to an Atlas conversation session, not to one model
    // run. Keeping the reference lets a new AgentLoop continue prior turns.
    this.conversation = Array.isArray(conversation) ? conversation : [];
    // Model context window budget (approximate token limit).
    this.contextWindowTokens = settings.contextWindowTokens || 32768;
  }

  // ── Public API ─────────────────────────────────────────────────────────────

  cancel() {
    this.cancellation.cancel();
    if (this.permissionManager) {
      this.permissionManager.cancelAllPending('Agent loop cancelled by user');
    }
    if (this.callbacks.onProgress) {
      this.callbacks.onProgress('Agent execution cancelled');
    }
  }

  // Backward-compat shim
  get cancelled() { return this.cancellation.cancelled; }

  async run(prompt, ideContext = {}) {
    this.cancellation = new CancellationToken();
    const systemPrompt = buildAgentSystemPrompt(ideContext, this.settings);

    if (this.conversation.length === 0) {
      this.conversation.push({ role: 'system', content: systemPrompt });
    } else if (this.conversation[0].role === 'system') {
      this.conversation[0] = { role: 'system', content: systemPrompt };
    } else {
      this.conversation.unshift({ role: 'system', content: systemPrompt });
    }
    this.conversation.push({ role: 'user', content: prompt });

    let iteration = 0;

    if (this.callbacks.onProgress) {
      this.callbacks.onProgress(`Starting agent task: "${prompt.substring(0, 50)}..."`);
    }

    while (iteration < this.maxIterations && !this.cancellation.cancelled) {
      iteration++;

      if (this.callbacks.onProgress) {
        this.callbacks.onProgress(`Step ${iteration}/${this.maxIterations}: Model reasoning...`);
      }

      // Context compaction: trim conversation if approaching context limit
      this.conversation = compactConversation(this.conversation, this.contextWindowTokens);

      // Call AI model with current conversation and available tools
      const response = await this._callModelWithTools();

      if (this.cancellation.cancelled) break;

      if (!response) {
        const finalAnswer = 'The AI provider returned an empty response. You can retry without losing this conversation.';
        this.conversation.push({ role: 'assistant', content: finalAnswer });
        if (this.callbacks.onComplete) {
          this.callbacks.onComplete({ content: finalAnswer, iterations: iteration });
        }
        return { content: finalAnswer, iterations: iteration };
      }

      // Check if model returned tool calls or text response
      if (response.toolCalls && response.toolCalls.length > 0) {
        this.conversation.push({
          role: 'assistant',
          content: response.content || null,
          tool_calls: response.toolCalls,
        });

        // Separate write_file calls (serial) from all others (parallel)
        const writeFileCalls = response.toolCalls.filter((tc) => tc.function?.name === 'write_file');
        const parallelCalls  = response.toolCalls.filter((tc) => tc.function?.name !== 'write_file');

        // Execute non-write calls in parallel
        const parallelResults = await Promise.all(
          parallelCalls.map((tc) => this._executeToolCall(tc, iteration))
        );
        for (const r of parallelResults) {
          if (r) this.conversation.push(r);
        }

        // Execute write_file calls serially (to avoid races on same path)
        for (const tc of writeFileCalls) {
          if (this.cancellation.cancelled) break;
          const r = await this._executeToolCall(tc, iteration);
          if (r) this.conversation.push(r);
        }

        // Test-loop: if run_tests returned failures, continue the loop
        const testResult = this._findTestFailureResult();
        if (testResult) {
          this.conversation.push({
            role: 'user',
            content: `[Test loop] The previous test run had failures:\n${testResult}\nPlease inspect the failures and fix them, then run tests again.`,
          });
          if (this.callbacks.onProgress) {
            this.callbacks.onProgress(`Test loop: failures detected — attempting auto-fix...`);
          }
          continue;   // Keep iterating
        }

      } else {
        // Model provided final text answer (no more tool calls)
        const finalAnswer = response.content || 'Task completed.';
        this.conversation.push({ role: 'assistant', content: finalAnswer });

        if (this.callbacks.onComplete) {
          this.callbacks.onComplete({
            content: finalAnswer,
            iterations: iteration,
          });
        }
        return { content: finalAnswer, iterations: iteration };
      }
    }

    if (iteration >= this.maxIterations && !this.cancellation.cancelled) {
      const limitMsg = `Agent reached maximum iteration limit (${this.maxIterations}).`;
      if (this.callbacks.onComplete) {
        this.callbacks.onComplete({ content: limitMsg, iterations: iteration });
      }
      return { content: limitMsg, iterations: iteration };
    }

    return { content: 'Agent stopped.', iterations: iteration };
  }

  // ── Private: model call (streaming-aware) ─────────────────────────────────

  async _callModelWithTools() {
    const aiProviders = require('../ai_providers');
    const tools = this.toolRegistry.getOpenAiToolDefinitions();
    const providerSettings = { ...this.settings, tools };

    // Use streaming when the provider supports it
    if (this.callbacks.onToken && this.settings.aiProvider !== 'builtIn') {
      return new Promise((resolve) => {
        let fullText = '';
        let streamedToolCalls = null;

        aiProviders.callAiProviderStreaming(providerSettings, this.conversation, {
          tools,
          onToken: (token) => {
            fullText += token;
            if (this.callbacks.onToken) this.callbacks.onToken(token);
          },
          onComplete: (err, text, toolCalls) => {
            if (err) {
              resolve({ content: `Error from AI provider: ${err.message}` });
            } else {
              resolve({
                content: text || null,
                toolCalls: toolCalls || null,
              });
            }
          },
        });
      });
    }

    // Non-streaming fallback (with retry)
    return new Promise((resolve) => {
      const attempt = () => new Promise((res, rej) => {
        aiProviders.callAiProviderWithTools(providerSettings, this.conversation, (err, response) => {
          if (err) rej(err); else res(response);
        });
      });

      aiProviders.callWithRetry(attempt, { label: 'AgentLoop.callModelWithTools' })
        .then(resolve)
        .catch((err) => resolve({ content: `Error from AI provider: ${err.message}` }));
    });
  }

  // ── Private: single tool execution ───────────────────────────────────────

  async _executeToolCall(toolCall, iteration) {
    const toolName = toolCall.function.name;
    let toolArgs = {};
    try {
      toolArgs = typeof toolCall.function.arguments === 'string'
        ? JSON.parse(toolCall.function.arguments)
        : toolCall.function.arguments || {};
    } catch (e) {
      toolArgs = {};
    }

    if (this.callbacks.onToolCall) {
      this.callbacks.onToolCall({ id: toolCall.id, toolName, args: toolArgs, iteration });
    }

    // Special diff intercept for write_file (whole-file replacement path)
    if (toolName === 'write_file' && toolArgs.content && this.callbacks.onDiffProposal) {
      const filesystem = require('../filesystem');
      let origContent = '';
      try { origContent = filesystem.readFile(this.workspaceRoot, toolArgs.path); } catch {}

      const diffData = generateUnifiedDiff(toolArgs.path, origContent, toolArgs.content);
      if (diffData.hasChanges) {
        const diffAccepted = await this.callbacks.onDiffProposal({
          path: toolArgs.path,
          diff: diffData.diff,
          hunks: diffData.hunks,
        });

        if (!diffAccepted) {
          this.cancellation.throwIfCancelled();
          const toolMessage = {
            role: 'tool',
            tool_call_id: toolCall.id,
            content: JSON.stringify({ error: `User rejected file modification diff for ${toolArgs.path}` }),
          };
          if (this.callbacks.onToolResult) {
            this.callbacks.onToolResult({ id: toolCall.id, toolName, result: { rejected: true }, iteration });
          }
          return toolMessage;
        }
      }
    }

    // Execute tool
    const toolResult = await this.toolRegistry.executeTool(toolName, toolArgs, {
      workspaceRoot: this.workspaceRoot,
      permissionManager: this.permissionManager,
      cancellationToken: this.cancellation,
      onRequestApproval: async (approvalReq) => {
        if (this.callbacks.onRequestApproval) {
          return await this.callbacks.onRequestApproval(approvalReq);
        }
        return { allowed: true };
      },
    });

    if (this.callbacks.onToolResult) {
      this.callbacks.onToolResult({ id: toolCall.id, toolName, result: toolResult, iteration });
    }

    // Store tool result for test-loop inspection
    if (toolName === 'run_tests') {
      this._lastTestResult = toolResult;
    }

    return {
      role: 'tool',
      tool_call_id: toolCall.id,
      content: JSON.stringify(toolResult),
    };
  }

  // ── Private: test loop helper ─────────────────────────────────────────────

  _findTestFailureResult() {
    if (!this._lastTestResult) return null;
    const result = this._lastTestResult;
    this._lastTestResult = null;
    if (result && result.failed > 0) {
      const lines = (result.errors || []).map((e) => `• ${e.file}:${e.line}: ${e.message}`).join('\n');
      return lines || `${result.failed} test(s) failed.`;
    }
    return null;
  }
}

module.exports = { AgentLoop };
