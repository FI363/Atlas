const { buildAgentSystemPrompt } = require('./context_builder');
const { generateUnifiedDiff } = require('./diff_engine');

class AgentLoop {
  constructor({ workspaceRoot, permissionManager, toolRegistry, callbacks, settings = {} }) {
    this.workspaceRoot = workspaceRoot;
    this.permissionManager = permissionManager;
    this.toolRegistry = toolRegistry;
    this.callbacks = callbacks || {};
    this.settings = settings;
    this.maxIterations = settings.agentMaxIterations || 25;
    this.cancelled = false;
    this.conversation = [];
  }

  cancel() {
    this.cancelled = true;
    if (this.permissionManager) {
      this.permissionManager.cancelAllPending('Agent loop cancelled by user');
    }
    if (this.callbacks.onProgress) {
      this.callbacks.onProgress('Agent execution cancelled');
    }
  }

  async run(prompt, ideContext = {}) {
    this.cancelled = false;
    const systemPrompt = buildAgentSystemPrompt(ideContext, this.settings);

    this.conversation = [
      { role: 'system', content: systemPrompt },
      { role: 'user', content: prompt }
    ];

    let iteration = 0;

    if (this.callbacks.onProgress) {
      this.callbacks.onProgress(`Starting agent task: "${prompt.substring(0, 50)}..."`);
    }

    while (iteration < this.maxIterations && !this.cancelled) {
      iteration++;

      if (this.callbacks.onProgress) {
        this.callbacks.onProgress(`Step ${iteration}/${this.maxIterations}: Model reasoning...`);
      }

      // Call AI model with current conversation and available tools
      const response = await this.callModelWithTools();

      if (this.cancelled) break;

      if (!response) {
        if (this.callbacks.onError) {
          this.callbacks.onError('Model returned an empty response.');
        }
        break;
      }

      // Check if model returned tool calls or text response
      if (response.toolCalls && response.toolCalls.length > 0) {
        // Add model assistant message with tool calls to history
        this.conversation.push({
          role: 'assistant',
          content: response.content || null,
          tool_calls: response.toolCalls,
        });

        // Execute each tool call
        for (const toolCall of response.toolCalls) {
          if (this.cancelled) break;

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
            this.callbacks.onToolCall({
              id: toolCall.id,
              toolName,
              args: toolArgs,
              iteration,
            });
          }

          // Special diff intercept for write_file
          if (toolName === 'write_file' && this.callbacks.onDiffProposal) {
            const filesystem = require('../filesystem');
            let origContent = '';
            try {
              origContent = filesystem.readFile(this.workspaceRoot, toolArgs.path);
            } catch {}

            const diffData = generateUnifiedDiff(toolArgs.path, origContent, toolArgs.content);
            if (diffData.hasChanges) {
              const diffAccepted = await this.callbacks.onDiffProposal({
                path: toolArgs.path,
                diff: diffData.diff,
                hunks: diffData.hunks,
              });

              if (!diffAccepted) {
                this.conversation.push({
                  role: 'tool',
                  tool_call_id: toolCall.id,
                  content: JSON.stringify({ error: `User rejected file modification diff for ${toolArgs.path}` }),
                });
                continue;
              }
            }
          }

          // Execute tool with context
          const toolResult = await this.toolRegistry.executeTool(toolName, toolArgs, {
            workspaceRoot: this.workspaceRoot,
            permissionManager: this.permissionManager,
            onRequestApproval: async (approvalReq) => {
              if (this.callbacks.onRequestApproval) {
                return await this.callbacks.onRequestApproval(approvalReq);
              }
              return { allowed: true };
            },
          });

          if (this.callbacks.onToolResult) {
            this.callbacks.onToolResult({
              id: toolCall.id,
              toolName,
              result: toolResult,
              iteration,
            });
          }

          // Add tool response to conversation
          this.conversation.push({
            role: 'tool',
            tool_call_id: toolCall.id,
            content: JSON.stringify(toolResult),
          });
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

    if (iteration >= this.maxIterations && !this.cancelled) {
      const limitMsg = `Agent reached maximum iteration limit (${this.maxIterations}).`;
      if (this.callbacks.onComplete) {
        this.callbacks.onComplete({ content: limitMsg, iterations: iteration });
      }
      return { content: limitMsg, iterations: iteration };
    }

    return { content: 'Agent stopped.', iterations: iteration };
  }

  async callModelWithTools() {
    const aiProviders = require('../ai_providers');
    const tools = this.toolRegistry.getOpenAiToolDefinitions();

    return new Promise((resolve) => {
      // Pass tool definitions to the provider
      const providerSettings = { ...this.settings, tools };
      
      // Use existing callAiProvider dispatcher with tool parameters
      aiProviders.callAiProviderWithTools(providerSettings, this.conversation, (err, response) => {
        if (err) {
          resolve({ content: `Error from AI provider: ${err.message}` });
        } else {
          resolve(response);
        }
      });
    });
  }
}

module.exports = { AgentLoop };
