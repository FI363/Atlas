const git = require('../../git');

function registerGitTools(registry) {
  registry.registerTool({
    name: 'git_status',
    description: 'Get working tree Git status and active branch.',
    inputSchema: {
      type: 'object',
      properties: {},
      required: [],
    },
    async execute(args, context) {
      return await git.getStatus(context.workspaceRoot);
    },
  });

  registry.registerTool({
    name: 'git_diff',
    description: 'Get Git diff for modified files.',
    inputSchema: {
      type: 'object',
      properties: {
        staged: { type: 'boolean', description: 'Show staged changes if true' },
        filePath: { type: 'string', description: 'Specific relative file path (optional)' },
      },
      required: [],
    },
    async execute(args, context) {
      const diffText = await git.getDiff(context.workspaceRoot, args);
      return { diff: diffText };
    },
  });

  registry.registerTool({
    name: 'git_log',
    description: 'Get recent Git commit history.',
    inputSchema: {
      type: 'object',
      properties: {
        maxCount: { type: 'number', description: 'Number of commits to retrieve (default: 10)' },
      },
      required: [],
    },
    async execute(args, context) {
      const commits = await git.getLog(context.workspaceRoot, args.maxCount || 10);
      return { commits };
    },
  });
}

module.exports = { registerGitTools };
