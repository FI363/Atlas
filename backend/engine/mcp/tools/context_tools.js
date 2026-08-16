const fs = require('fs');
const path = require('path');
const filesystem = require('../../filesystem');
const terminal = require('../../terminal');

function registerContextTools(registry) {
  registry.registerTool({
    name: 'get_project_info',
    description: 'Inspect project configuration (pubspec.yaml, package.json, project structure).',
    inputSchema: {
      type: 'object',
      properties: {},
      required: [],
    },
    async execute(args, context) {
      const root = context.workspaceRoot;
      const info = {
        projectName: path.basename(root),
        root,
        projectType: 'unknown',
        manifest: null,
      };

      const pubspecPath = path.join(root, 'pubspec.yaml');
      const packagePath = path.join(root, 'package.json');

      if (fs.existsSync(pubspecPath)) {
        info.projectType = 'flutter_dart';
        info.manifest = fs.readFileSync(pubspecPath, 'utf-8').substring(0, 2000);
      } else if (fs.existsSync(packagePath)) {
        info.projectType = 'node_js';
        info.manifest = fs.readFileSync(packagePath, 'utf-8');
      }

      return info;
    },
  });

  registry.registerTool({
    name: 'get_workspace_structure',
    description: 'Get top-level directory structure tree.',
    inputSchema: {
      type: 'object',
      properties: {
        depth: { type: 'number', description: 'Depth level (default: 2)' },
      },
      required: [],
    },
    async execute(args, context) {
      const depth = args.depth || 2;
      const tree = filesystem.buildTree(context.workspaceRoot, 0, depth);
      return { tree };
    },
  });

  registry.registerTool({
    name: 'get_diagnostics',
    description: 'Get code errors/warnings for active project (LSP diagnostics).',
    inputSchema: {
      type: 'object',
      properties: {
        filePath: { type: 'string', description: 'Specific relative file path (optional)' },
      },
      required: [],
    },
    async execute(args, context) {
      const root = context.workspaceRoot;
      const pubspecPath = path.join(root, 'pubspec.yaml');

      if (fs.existsSync(pubspecPath)) {
        try {
          const res = await terminal.runCommandPromise('dart analyze --format=machine', root, 30000);
          const lines = (res.stdout || '').split('\n').filter(Boolean);
          const diagnostics = lines.map(line => {
            const parts = line.split('|');
            if (parts.length >= 8) {
              return {
                severity: parts[0],
                type: parts[1],
                name: parts[2],
                file: path.relative(root, parts[3]).replace(/\\/g, '/'),
                line: parseInt(parts[4], 10),
                column: parseInt(parts[5], 10),
                message: parts[7],
              };
            }
            return null;
          }).filter(Boolean);

          if (args.filePath) {
            return { diagnostics: diagnostics.filter(d => d.file === args.filePath) };
          }
          return { diagnostics };
        } catch (e) {
          return { diagnostics: [], message: `Dart analyzer failed: ${e.message}` };
        }
      }

      return { diagnostics: [], message: 'No active LSP diagnostics provider available for this project type.' };
    },
  });

  registry.registerTool({
    name: 'get_symbols',
    description: 'Get definitions and document symbols (LSP abstraction).',
    inputSchema: {
      type: 'object',
      properties: {
        filePath: { type: 'string', description: 'Relative path to inspect' },
      },
      required: ['filePath'],
    },
    async execute(args, context) {
      try {
        const content = filesystem.readFile(context.workspaceRoot, args.filePath);
        const lines = content.split('\n');
        const symbols = [];

        // Simple regex symbol extraction for Dart / JS / TS
        for (let i = 0; i < lines.length; i++) {
          const line = lines[i];
          const classMatch = line.match(/(?:class|enum|mixin|interface)\s+([A-Za-z0-9_]+)/);
          const funcMatch = line.match(/(?:void|Future|Widget|String|int|bool|dynamic|var|const|function)\s+([A-Za-z0-9_]+)\s*\(/);

          if (classMatch) {
            symbols.push({ name: classMatch[1], kind: 'class', line: i + 1 });
          } else if (funcMatch && !['if', 'for', 'while', 'switch'].includes(funcMatch[1])) {
            symbols.push({ name: funcMatch[1], kind: 'function', line: i + 1 });
          }
        }

        return { path: args.filePath, symbols };
      } catch (e) {
        return { error: `Failed to get symbols for ${args.filePath}: ${e.message}` };
      }
    },
  });
}

module.exports = { registerContextTools };
