class ToolRegistry {
  constructor() {
    this.tools = new Map();
  }

  registerTool(tool) {
    if (!tool.name || !tool.description || typeof tool.execute !== 'function') {
      throw new Error(`Invalid tool registration for ${tool.name || 'unnamed tool'}`);
    }
    this.tools.set(tool.name, tool);
  }

  getTool(name) {
    return this.tools.get(name);
  }

  listTools() {
    return Array.from(this.tools.values());
  }

  getOpenAiToolDefinitions() {
    return this.listTools().map(tool => ({
      type: 'function',
      function: {
        name: tool.name,
        description: tool.description,
        parameters: tool.inputSchema || {
          type: 'object',
          properties: {},
          required: [],
        },
      },
    }));
  }

  async executeTool(name, args, context = {}) {
    const tool = this.getTool(name);
    if (!tool) {
      throw new Error(`Tool '${name}' is not registered in Atlas MCP.`);
    }

    // Permission check
    if (context.permissionManager) {
      const permCheck = context.permissionManager.checkPermission(name, args);
      if (!permCheck.allowed) {
        if (permCheck.requiresApproval && context.onRequestApproval) {
          const approvalResult = await context.onRequestApproval({
            requestId: permCheck.requestId,
            toolName: name,
            args,
            category: permCheck.category,
          });

          if (!approvalResult.allowed) {
            return {
              error: `Permission denied for ${name}: ${approvalResult.reason || 'User rejected operation'}`,
              permissionDenied: true,
            };
          }
        } else {
          return {
            error: `Permission denied for ${name} (${permCheck.category})`,
            permissionDenied: true,
          };
        }
      }
    }

    try {
      const result = await tool.execute(args, context);
      return result;
    } catch (err) {
      return {
        error: `Tool '${name}' execution failed: ${err.message}`,
      };
    }
  }
}

const globalRegistry = new ToolRegistry();

module.exports = {
  ToolRegistry,
  globalRegistry,
};
