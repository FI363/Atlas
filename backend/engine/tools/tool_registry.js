const { PermissionLevels } = require('../permissions/permission_manager');

/**
 * Central Tool Registry for native IDE tools and future MCP extensions.
 */
class ToolRegistry {
  constructor() {
    /** @type {Map<string, { name: string, description: string, inputSchema: object, permission: string, execute: Function }>} */
    this._tools = new Map();
  }

  /**
   * Register a new tool.
   *
   * @param {object} tool
   * @param {string} tool.name Unique name (e.g. 'read_file', 'filesystem.read')
   * @param {string} tool.description What the tool does and when to use it
   * @param {object} tool.inputSchema JSON Schema of parameters
   * @param {string} [tool.permission=PermissionLevels.READ] Permission tier
   * @param {Function} tool.execute Async execution handler
   */
  registerTool(tool) {
    if (!tool.name || typeof tool.execute !== 'function') {
      throw new Error(`Invalid tool registration: missing name or execute function`);
    }

    this._tools.set(tool.name, {
      name: tool.name,
      description: tool.description || '',
      inputSchema: tool.inputSchema || { type: 'object', properties: {} },
      permission: tool.permission || PermissionLevels.READ,
      execute: tool.execute,
    });
  }

  /**
   * Unregister a tool by name.
   * @param {string} name
   */
  unregisterTool(name) {
    this._tools.delete(name);
  }

  /**
   * Get a registered tool definition.
   * @param {string} name
   */
  getTool(name) {
    return this._tools.get(name);
  }

  /**
   * Check if a tool is registered.
   * @param {string} name
   */
  hasTool(name) {
    return this._tools.has(name);
  }

  /**
   * Get all registered tools formatted for LLM function calling declarations.
   * Returns standard OpenAI/Gemini compatible tool definitions.
   *
   * @returns {Array<{ type: 'function', function: { name: string, description: string, parameters: object } }>}
   */
  getToolDeclarations() {
    const declarations = [];
    for (const tool of this._tools.values()) {
      declarations.push({
        type: 'function',
        function: {
          name: tool.name,
          description: tool.description,
          parameters: tool.inputSchema,
        },
      });
    }
    return declarations;
  }

  /**
   * Execute a tool by name with permission check and cancellation support.
   *
   * @param {string} name Tool name
   * @param {object} args Input arguments
   * @param {object} context Execution context (workspaceRoot, cancellationToken, etc.)
   * @returns {Promise<any>} Tool execution result
   */
  async executeTool(name, args = {}, context = {}) {
    const tool = this._tools.get(name);
    if (!tool) {
      throw new Error(`Tool "${name}" not found in Tool Registry`);
    }

    if (context.cancellationToken?.cancelled) {
      throw new Error(`Tool execution for "${name}" cancelled`);
    }

    try {
      const result = await tool.execute({
        args: args || {},
        workspaceRoot: context.workspaceRoot || process.cwd(),
        context,
        cancellationToken: context.cancellationToken,
      });
      return result;
    } catch (err) {
      return {
        error: true,
        message: err.message || `Execution error in tool ${name}`,
      };
    }
  }

  /**
   * Returns list of all registered tool metadata.
   */
  listTools() {
    return Array.from(this._tools.values()).map((t) => ({
      name: t.name,
      description: t.description,
      permission: t.permission,
      inputSchema: t.inputSchema,
    }));
  }
}

module.exports = {
  ToolRegistry,
};
