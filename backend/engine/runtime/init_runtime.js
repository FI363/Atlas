const { EventBus } = require('./event_bus');
const { AgentRuntime } = require('./agent_runtime');
const { ProviderManager } = require('../providers/provider_manager');
const { GeminiProvider } = require('../providers/gemini_provider');
const { ClaudeProvider } = require('../providers/claude_provider');
const { OpenAIProvider } = require('../providers/openai_provider');
const { OpenRouterProvider } = require('../providers/openrouter_provider');
const { LocalProvider } = require('../providers/local_provider');
const { RemoteProvider } = require('../providers/remote_provider');
const { ToolRegistry } = require('../tools/tool_registry');
const { registerIdeTools } = require('../tools/ide_tool_adapter');
const { PermissionManager } = require('../permissions/permission_manager');
const { ContextManager } = require('../context/context_manager');
const { SessionManager } = require('../session/session_manager');

/**
 * Initializes and wires the complete Agent Runtime ecosystem.
 *
 * @param {object} [options]
 * @param {string} [options.permissionPolicy='approve_write']
 * @param {number} [options.maxContextTokens=32768]
 * @returns {{
 *   eventBus: EventBus,
 *   providerManager: ProviderManager,
 *   toolRegistry: ToolRegistry,
 *   permissionManager: PermissionManager,
 *   contextManager: ContextManager,
 *   sessionManager: SessionManager,
 *   agentRuntime: AgentRuntime
 * }}
 */
function initializeAgentRuntime(options = {}) {
  const eventBus = new EventBus();
  const providerManager = new ProviderManager();

  // Register all model providers
  providerManager.registerProvider('gemini', GeminiProvider);
  providerManager.registerProvider('claude', ClaudeProvider);
  providerManager.registerProvider('anthropic', ClaudeProvider); // alias
  providerManager.registerProvider('openai', OpenAIProvider);
  providerManager.registerProvider('openrouter', OpenRouterProvider);
  providerManager.registerProvider('openRouter', OpenRouterProvider); // alias
  providerManager.registerProvider('local', LocalProvider);
  providerManager.registerProvider('ollama', LocalProvider); // alias
  providerManager.registerProvider('remote', RemoteProvider);
  providerManager.registerProvider('custom', RemoteProvider); // alias

  // Initialize and register native IDE tools
  const toolRegistry = new ToolRegistry();
  registerIdeTools(toolRegistry);

  const permissionManager = new PermissionManager(options.permissionPolicy || 'approve_write');
  const contextManager = new ContextManager({ maxContextTokens: options.maxContextTokens || 32768 });
  const sessionManager = new SessionManager();

  const agentRuntime = new AgentRuntime({
    eventBus,
    providerManager,
    toolRegistry,
    permissionManager,
    contextManager,
  });

  return {
    eventBus,
    providerManager,
    toolRegistry,
    permissionManager,
    contextManager,
    sessionManager,
    agentRuntime,
  };
}

module.exports = {
  initializeAgentRuntime,
};
