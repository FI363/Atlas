const { AgentEvents } = require('./event_bus');
const { CancellationToken } = require('../agent/cancellation_token');

const MAX_ITERATIONS = 25;
const MAX_TOOL_CALLS = 50;

class AgentRuntime {
  /**
   * @param {object} params
   * @param {import('./event_bus').EventBus} params.eventBus
   * @param {import('../providers/provider_manager').ProviderManager} params.providerManager
   * @param {import('../tools/tool_registry').ToolRegistry} params.toolRegistry
   * @param {import('../permissions/permission_manager').PermissionManager} params.permissionManager
   * @param {import('../context/context_manager').ContextManager} params.contextManager
   */
  constructor({ eventBus, providerManager, toolRegistry, permissionManager, contextManager }) {
    this.eventBus = eventBus;
    this.providerManager = providerManager;
    this.toolRegistry = toolRegistry;
    this.permissionManager = permissionManager;
    this.contextManager = contextManager;

    /** @type {CancellationToken|null} */
    this._cancellationToken = null;
    this._isRunning = false;
  }

  get isRunning() {
    return this._isRunning;
  }

  /**
   * Cancel currently running agent execution.
   */
  cancel() {
    if (this._cancellationToken) {
      this._cancellationToken.cancel();
    }
    this.permissionManager.cancelAllPending('Agent execution cancelled by user');
    this.eventBus.emitEvent(AgentEvents.CANCELLED, { reason: 'User cancelled execution' });
    this._isRunning = false;
  }

  /**
   * Execute a multi-turn agent task.
   *
   * @param {object} params
   * @param {string} params.prompt User prompt
   * @param {import('../session/session_manager').AgentSession} params.session Active session
   * @param {object} [params.ideContext={}] Workspace context (activeFile, selection, etc.)
   * @param {object} [params.settings={}] User settings (temperature, policy, etc.)
   * @param {string} [params.providerId] Optional override provider
   * @param {string} [params.modelId] Optional override model
   * @returns {Promise<{ content: string, iterations: number, toolCallsCount: number }>}
   */
  async start({ prompt, session, ideContext = {}, settings = {}, providerId, modelId }) {
    if (this._isRunning) {
      throw new Error('An agent task is already running. Cancel it or wait for completion.');
    }

    this._isRunning = true;
    this._cancellationToken = new CancellationToken();

    const pId = providerId || session.providerId || settings.aiProvider || 'gemini';
    const mId = modelId || session.modelId || settings.geminiModel || settings.openRouterModel || 'gemini-2.5-flash';

    session.switchModel(pId, mId);
    session.startRun(prompt);

    this.eventBus.emitEvent(AgentEvents.STARTED, {
      sessionId: session.sessionId,
      task: prompt,
      providerId: pId,
      modelId: mId,
    });

    try {
      // 1. Build and set System Prompt
      const systemPrompt = this.contextManager.buildSystemPrompt(ideContext, settings);
      if (session.conversation.length === 0) {
        session.addMessage({ role: 'system', content: systemPrompt });
      } else if (session.conversation[0].role === 'system') {
        session.conversation[0].content = systemPrompt;
      } else {
        session.conversation.unshift({ role: 'system', content: systemPrompt });
      }

      // 2. Append User Prompt
      session.addMessage({ role: 'user', content: prompt });

      // 3. Resolve Provider
      const providerConfig = {
        apiKey: settings.geminiApiKey || settings.openRouterApiKey || settings.openAiApiKey || settings.anthropicApiKey || settings.customApiKey || '',
        endpoint: settings.openRouterEndpoint || settings.customAgentEndpoint || settings.ollamaEndpoint || '',
        model: mId,
        temperature: settings.aiTemperature ?? 0.2,
        maxTokens: settings.aiMaxTokens ?? 4096,
      };
      const provider = this.providerManager.getProvider(pId, providerConfig);

      let iteration = 0;
      let totalToolCalls = 0;
      let finalContent = '';

      // 4. Main ReAct Execution Loop
      while (iteration < MAX_ITERATIONS && !this._cancellationToken.cancelled) {
        iteration++;

        // Compact conversation if token limit approached
        session.conversation = this.contextManager.compactConversation(session.conversation);

        // Get tool declarations
        const toolDeclarations = this.toolRegistry.getToolDeclarations();

        // Call model
        const response = await provider.send({
          messages: session.conversation,
          tools: toolDeclarations,
          options: { model: mId, temperature: settings.aiTemperature },
          cancellationToken: this._cancellationToken,
        });

        if (this._cancellationToken.cancelled) break;

        if (!response) {
          throw new Error('Model provider returned an empty response.');
        }

        const { content, toolCalls } = response;

        // If the model produced a message
        if (content) {
          finalContent = content;
          this.eventBus.emitEvent(AgentEvents.MESSAGE, {
            content,
            iteration,
            sessionId: session.sessionId,
          });
        }

        // Check if there are tool calls
        if (!toolCalls || toolCalls.length === 0) {
          // Model is done with reasoning and provided the final response
          session.addMessage({ role: 'assistant', content: content || finalContent });
          session.finishRun('completed');

          this.eventBus.emitEvent(AgentEvents.COMPLETED, {
            content: content || finalContent,
            iterations: iteration,
            toolCallsCount: totalToolCalls,
            sessionId: session.sessionId,
          });

          this._isRunning = false;
          return {
            content: content || finalContent,
            iterations: iteration,
            toolCallsCount: totalToolCalls,
          };
        }

        // Record assistant turn with tool calls
        session.addMessage({
          role: 'assistant',
          content: content || null,
          tool_calls: toolCalls.map((tc) => ({
            id: tc.id,
            type: 'function',
            function: {
              name: tc.name,
              arguments: JSON.stringify(tc.args || {}),
            },
          })),
        });

        // Execute tool calls
        for (const tc of toolCalls) {
          if (this._cancellationToken.cancelled) break;
          totalToolCalls++;
          if (totalToolCalls > MAX_TOOL_CALLS) {
            throw new Error(`Exceeded maximum tool call limit (${MAX_TOOL_CALLS})`);
          }

          const toolDef = this.toolRegistry.getTool(tc.name);
          const toolPermLevel = toolDef?.permission || 'READ';

          this.eventBus.emitEvent(AgentEvents.TOOL_CALL, {
            id: tc.id,
            toolName: tc.name,
            args: tc.args,
            iteration,
            sessionId: session.sessionId,
          });

          // Check permissions
          const permCheck = this.permissionManager.checkPermission(toolPermLevel, tc.name, tc.args);
          if (permCheck.denied) {
            const deniedResult = { error: true, message: `Permission denied for ${tc.name}` };
            session.addMessage({
              role: 'tool',
              tool_call_id: tc.id,
              name: tc.name,
              content: JSON.stringify(deniedResult),
            });
            session.recordToolExecution(tc, deniedResult);
            continue;
          }

          if (permCheck.requiresApproval) {
            this.eventBus.emitEvent(AgentEvents.PERMISSION_REQUESTED, {
              requestId: tc.id,
              toolName: tc.name,
              args: tc.args,
              level: toolPermLevel,
              sessionId: session.sessionId,
            });

            const approval = await this.permissionManager.createPendingApproval(tc.id, tc.name, tc.args, toolPermLevel);
            this.eventBus.emitEvent(AgentEvents.PERMISSION_RESOLVED, {
              requestId: tc.id,
              approved: approval.approved,
              sessionId: session.sessionId,
            });

            if (!approval.approved) {
              const deniedResult = { error: true, message: approval.reason || `Action cancelled by user` };
              session.addMessage({
                role: 'tool',
                tool_call_id: tc.id,
                name: tc.name,
                content: JSON.stringify(deniedResult),
              });
              session.recordToolExecution(tc, deniedResult);
              continue;
            }
          }

          // Execute tool
          const result = await this.toolRegistry.executeTool(tc.name, tc.args, {
            workspaceRoot: session.workspaceRoot,
            cancellationToken: this._cancellationToken,
          });

          this.eventBus.emitEvent(AgentEvents.TOOL_RESULT, {
            id: tc.id,
            toolName: tc.name,
            result,
            iteration,
            sessionId: session.sessionId,
          });

          if (tc.name === 'write_file' || tc.name === 'create_file' || tc.name === 'delete_file') {
            this.eventBus.emitEvent(AgentEvents.FILE_CHANGED, {
              path: tc.args.path,
              action: tc.name,
              sessionId: session.sessionId,
            });
          }

          session.addMessage({
            role: 'tool',
            tool_call_id: tc.id,
            name: tc.name,
            content: typeof result === 'string' ? result : JSON.stringify(result),
          });
          session.recordToolExecution(tc, result);
        }
      }

      if (this._cancellationToken.cancelled) {
        session.finishRun('cancelled');
        this._isRunning = false;
        return { content: 'Agent cancelled by user', iterations: iteration, toolCallsCount: totalToolCalls };
      }

      session.finishRun('completed');
      this._isRunning = false;
      return { content: finalContent, iterations: iteration, toolCallsCount: totalToolCalls };
    } catch (err) {
      session.finishRun('error');
      this._isRunning = false;
      this.eventBus.emitEvent(AgentEvents.FAILED, {
        error: err.message,
        sessionId: session.sessionId,
      });
      throw err;
    }
  }
}

module.exports = {
  AgentRuntime,
};
