const filesystem = require('../../filesystem');
const { applyPatch } = require('../../agent/patch_engine');

function registerFilesystemTools(registry) {
  registry.registerTool({
    name: 'list_directory',
    description: 'List contents of a directory in the workspace. Returns filenames, types, and sizes.',
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
    description: 'Read the full contents of a file in the workspace.',
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
    name: 'read_file_range',
    description: 'Read a specific line range from a file. Efficient for large files — avoids loading the entire content.',
    inputSchema: {
      type: 'object',
      properties: {
        path:      { type: 'string', description: 'Relative file path' },
        startLine: { type: 'number', description: '1-based start line (inclusive)' },
        endLine:   { type: 'number', description: '1-based end line (inclusive)' },
      },
      required: ['path', 'startLine', 'endLine'],
    },
    async execute(args, context) {
      const content = filesystem.readFile(context.workspaceRoot, args.path);
      const lines   = content.split('\n');
      const start   = Math.max(1, Math.floor(args.startLine)) - 1;
      const end     = Math.min(lines.length, Math.floor(args.endLine));
      const slice   = lines.slice(start, end).join('\n');
      return {
        path: args.path,
        startLine: start + 1,
        endLine: end,
        totalLines: lines.length,
        content: slice,
      };
    },
  });

  registry.registerTool({
    name: 'write_file',
    description: [
      'Write content to a file. Two modes:',
      '  1. Whole-file replacement: provide `content` (full file text). A diff will be shown to the user.',
      '  2. Patch mode: provide `patch` (unified diff string). Only changed lines are applied.',
      'Prefer patch mode for targeted edits to large files.',
    ].join('\n'),
    inputSchema: {
      type: 'object',
      properties: {
        path:    { type: 'string', description: 'Relative file path' },
        content: { type: 'string', description: 'Full new file content (use for new files or complete rewrites)' },
        patch:   { type: 'string', description: 'Unified diff string to apply (use for targeted edits)' },
      },
      required: ['path'],
    },
    async execute(args, context) {
      if (args.patch) {
        // Patch mode
        const result = applyPatch(context.workspaceRoot, args.path, args.patch);
        return result;
      }

      // Whole-file mode
      let originalContent = '';
      try {
        originalContent = filesystem.readFile(context.workspaceRoot, args.path);
      } catch { /* New file */ }

      filesystem.writeFile(context.workspaceRoot, args.path, args.content || '');
      return {
        path: args.path,
        success: true,
        bytesWritten: Buffer.byteLength(args.content || '', 'utf-8'),
        previousContent: originalContent,
      };
    },
  });

  registry.registerTool({
    name: 'apply_patch',
    description: 'Apply a unified diff patch to a file without replacing the whole file. Use this for surgical edits.',
    inputSchema: {
      type: 'object',
      properties: {
        path:  { type: 'string', description: 'Relative file path to patch' },
        patch: { type: 'string', description: 'Unified diff string (output of diff -u)' },
      },
      required: ['path', 'patch'],
    },
    async execute(args, context) {
      return applyPatch(context.workspaceRoot, args.path, args.patch);
    },
  });

  registry.registerTool({
    name: 'create_file',
    description: 'Create a new file or directory in the workspace.',
    inputSchema: {
      type: 'object',
      properties: {
        path:        { type: 'string',  description: 'Relative path for the new entry' },
        isDirectory: { type: 'boolean', description: 'True if creating a folder' },
        content:     { type: 'string',  description: 'Optional initial content for new files' },
      },
      required: ['path'],
    },
    async execute(args, context) {
      filesystem.createWorkspaceEntry(context.workspaceRoot, args.path, !!args.isDirectory);
      if (!args.isDirectory && args.content) {
        filesystem.writeFile(context.workspaceRoot, args.path, args.content);
      }
      return { path: args.path, created: true, isDirectory: !!args.isDirectory };
    },
  });

  registry.registerTool({
    name: 'delete_file',
    description: 'Permanently delete a file or directory from the workspace. This cannot be undone.',
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
        sourcePath:      { type: 'string', description: 'Source relative path' },
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
