/**
 * Base abstract class for all AI Model Providers in the Atlas Agent Runtime.
 *
 * Every provider must implement this interface cleanly. The Agent Runtime
 * must NEVER contain provider-specific branching logic.
 */
class ModelProvider {
  /**
   * @param {object} config Provider configuration (e.g. apiKey, endpoint, defaultModel)
   */
  constructor(config = {}) {
    if (new.target === ModelProvider) {
      throw new TypeError('Cannot construct ModelProvider instances directly');
    }
    this.config = config;
  }

  /**
   * Unique identifier for this provider (e.g. 'gemini', 'claude', 'openai', 'openrouter', 'local', 'remote')
   * @returns {string}
   */
  get id() {
    throw new Error('Getter id must be implemented by subclass');
  }

  /**
   * Human-readable name (e.g. 'Google Gemini', 'Anthropic Claude')
   * @returns {string}
   */
  get name() {
    throw new Error('Getter name must be implemented by subclass');
  }

  /**
   * Supported model identifiers
   * @returns {string[]}
   */
  get models() {
    return [];
  }

  /**
   * Provider capabilities
   * @returns {{ streaming: boolean, toolCalling: boolean, vision: boolean }}
   */
  get capabilities() {
    return {
      streaming: true,
      toolCalling: true,
      vision: false,
    };
  }

  /**
   * Sends a request to the model and waits for the full response.
   *
   * @param {object} params
   * @param {Array<{role: string, content: string|Array}>} params.messages Conversation history
   * @param {Array<object>} params.tools Available tool definitions
   * @param {object} [params.options] Generation options (temperature, maxTokens, model)
   * @param {object} [params.cancellationToken] Cooperative cancellation token
   * @returns {Promise<{ content: string|null, toolCalls: Array<{ id: string, name: string, args: object }>, rawResponse?: any }>}
   */
  async send({ messages, tools = [], options = {}, cancellationToken = null }) {
    throw new Error('send() must be implemented by subclass');
  }

  /**
   * Streams a request from the model.
   *
   * @param {object} params
   * @param {Array<{role: string, content: string|Array}>} params.messages Conversation history
   * @param {Array<object>} params.tools Available tool definitions
   * @param {object} [params.options] Generation options
   * @param {object} [params.cancellationToken] Cancellation token
   * @param {Function} [params.onToken] Callback (token: string) => void
   * @param {Function} [params.onToolCall] Callback (toolCall: object) => void
   * @returns {Promise<{ content: string, toolCalls: Array<object> }>}
   */
  async stream({ messages, tools = [], options = {}, cancellationToken = null, onToken = null, onToolCall = null }) {
    throw new Error('stream() must be implemented by subclass');
  }
}

module.exports = {
  ModelProvider,
};
