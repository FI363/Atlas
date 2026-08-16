const search = require('../../search');

function registerSearchTools(registry) {
  registry.registerTool({
    name: 'search_code',
    description: 'Search for a string or pattern across code files in the workspace.',
    inputSchema: {
      type: 'object',
      properties: {
        query: { type: 'string', description: 'Search term or symbol' },
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
    description: 'Find files in the workspace matching a path pattern or filename.',
    inputSchema: {
      type: 'object',
      properties: {
        pattern: { type: 'string', description: 'Filename or path substring pattern' },
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
}

module.exports = { registerSearchTools };
