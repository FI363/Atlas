const filesystem = require('../../filesystem');

function registerFilesystemTools(registry) {
  registry.registerTool({
    name: 'list_directory',
    description: 'List contents of a directory in the workspace.',
    inputSchema: {
      type: 'object',
      properties: {
        path: { type: 'string', description: 'Relative directory path (e.g. "." or "lib/widgets")' },
      },
      required: [],
    },
    async execute(args, context) {
      const relPath = args.path || '.';
      const entries = filesystem.listDirectory(context.workspaceRoot, relPath);
      return { path: relPath, entries };
    },
  });

  registry.registerTool({
    name: 'read_file',
    description: 'Read contents of a file in the workspace.',
    inputSchema: {
      type: 'object',
      properties: {
        path: { type: 'string', description: 'Relative file path (e.g. "lib/main.dart")' },
      },
      required: ['path'],
    },
    async execute(args, context) {
      const content = filesystem.readFile(context.workspaceRoot, args.path);
      return { path: args.path, content };
    },
  });

  registry.registerTool({
    name: 'write_file',
    description: 'Write content to a file in the workspace. Generates diff for user review if configured.',
    inputSchema: {
      type: 'object',
      properties: {
        path: { type: 'string', description: 'Relative file path' },
        content: { type: 'string', description: 'Full new text content to write to the file' },
      },
      required: ['path', 'content'],
    },
    async execute(args, context) {
      let originalContent = '';
      try {
        originalContent = filesystem.readFile(context.workspaceRoot, args.path);
      } catch {
        // File doesn't exist yet
      }

      filesystem.writeFile(context.workspaceRoot, args.path, args.content);
      return {
        path: args.path,
        success: true,
        bytesWritten: Buffer.byteLength(args.content, 'utf-8'),
        previousContent: originalContent,
      };
    },
  });

  registry.registerTool({
    name: 'create_file',
    description: 'Create a new file or directory in the workspace.',
    inputSchema: {
      type: 'object',
      properties: {
        path: { type: 'string', description: 'Relative path for the new entry' },
        isDirectory: { type: 'boolean', description: 'True if creating a folder' },
      },
      required: ['path'],
    },
    async execute(args, context) {
      filesystem.createWorkspaceEntry(context.workspaceRoot, args.path, !!args.isDirectory);
      return { path: args.path, created: true, isDirectory: !!args.isDirectory };
    },
  });

  registry.registerTool({
    name: 'delete_file',
    description: 'Delete a file or directory from the workspace.',
    inputSchema: {
      type: 'object',
      properties: {
        path: { type: 'string', description: 'Relative path to delete' },
      },
      required: ['path'],
    },
    async execute(args, context) {
      filesystem.deleteEntry(context.workspaceRoot, args.path);
      return { path: args.path, deleted: true };
    },
  });

  registry.registerTool({
    name: 'move_file',
    description: 'Move or rename a file/directory in the workspace.',
    inputSchema: {
      type: 'object',
      properties: {
        sourcePath: { type: 'string', description: 'Source relative path' },
        destinationPath: { type: 'string', description: 'Destination relative path' },
      },
      required: ['sourcePath', 'destinationPath'],
    },
    async execute(args, context) {
      filesystem.moveEntry(context.workspaceRoot, args.sourcePath, args.destinationPath);
      return { sourcePath: args.sourcePath, destinationPath: args.destinationPath, moved: true };
    },
  });
}

module.exports = { registerFilesystemTools };
