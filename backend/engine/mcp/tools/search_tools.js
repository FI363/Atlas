const search = require('../../search');

function registerSearchTools(registry) {
  registry.registerTool({
    name: 'search_code',
    description: 'Search for a string or pattern across code files in the workspace. Returns matching lines with file paths and line numbers.',
    inputSchema: {
      type: 'object',
      properties: {
        query:      { type: 'string', description: 'Search term or symbol name' },
        maxResults: { type: 'number', description: 'Max number of results to return (default: 50)' },
      },
      required: ['query'],
    },
    async execute(args, context) {
      const results = search.searchWorkspaceFiles(
        context.workspaceRoot,
        context.workspaceRoot,
        args.query,
        [],
        args.maxResults || 50
      );
      return { query: args.query, resultsCount: results.length, results };
    },
  });

  registry.registerTool({
    name: 'find_files',
    description: 'Find files in the workspace matching a path pattern or filename substring.',
    inputSchema: {
      type: 'object',
      properties: {
        pattern:    { type: 'string', description: 'Filename or path substring to match' },
        maxResults: { type: 'number', description: 'Max results (default 100)' },
      },
      required: [],
    },
    async execute(args, context) {
      const results = search.findFiles(
        context.workspaceRoot,
        context.workspaceRoot,
        args.pattern || '',
        [],
        args.maxResults || 100
      );
      return { pattern: args.pattern || '', resultsCount: results.length, files: results };
    },
  });

  registry.registerTool({
    name: 'search_symbols',
    description: 'Find function, class, or method definitions by name across the entire workspace. Returns file path, line number, and kind for each match.',
    inputSchema: {
      type: 'object',
      properties: {
        name: { type: 'string', description: 'Symbol name or partial name to search for (e.g. "AgentLoop", "buildPrompt")' },
      },
      required: ['name'],
    },
    async execute(args, context) {
      try {
        const { symbolIndex } = require('../../indexer/symbol_index');
        const matches = symbolIndex.findSymbol(args.name);
        return { name: args.name, count: matches.length, symbols: matches };
      } catch {
        return { name: args.name, count: 0, symbols: [], error: 'Symbol index not ready' };
      }
    },
  });

  registry.registerTool({
    name: 'list_recent_files',
    description: 'List the N most recently modified files in the workspace. Useful for finding where recent changes were made.',
    inputSchema: {
      type: 'object',
      properties: {
        n: { type: 'number', description: 'Number of files to return (default: 10, max: 50)' },
      },
      required: [],
    },
    async execute(args, context) {
      try {
        const { fileIndex } = require('../../indexer/file_index');
        const n = Math.min(args.n || 10, 50);
        const files = fileIndex.getRecentlyModified(n);
        return { count: files.length, files };
      } catch {
        return { count: 0, files: [], error: 'File index not ready' };
      }
    },
  });
}

module.exports = { registerSearchTools };

