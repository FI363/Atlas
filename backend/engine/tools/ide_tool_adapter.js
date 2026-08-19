const path = require('path');
const fs = require('fs');
const filesystemModule = require('../filesystem');
const terminalModule = require('../terminal');
const searchModule = require('../search');
const gitModule = require('../git');
const { PermissionLevels } = require('../permissions/permission_manager');

/**
 * Registers all standard host IDE tools onto a ToolRegistry instance.
 *
 * @param {import('./tool_registry').ToolRegistry} registry
 */
function registerIdeTools(registry) {
  // ── Filesystem: Read ────────────────────────────────────────────────────────
  registry.registerTool({
    name: 'read_file',
    description: 'Read the contents of a file at the specified workspace path. Use this to inspect code before modifying.',
    permission: PermissionLevels.READ,
    inputSchema: {
      type: 'object',
      properties: {
        path: {
          type: 'string',
          description: 'Relative path to the file within the workspace (e.g. "lib/main.dart" or "src/app.js")',
        },
        startLine: {
          type: 'integer',
          description: 'Optional 1-based start line number to read a specific slice',
        },
        endLine: {
          type: 'integer',
          description: 'Optional 1-based end line number (inclusive)',
        },
      },
      required: ['path'],
    },
    execute: async ({ args, workspaceRoot }) => {
      const targetPath = args.path;
      if (!targetPath) return { error: 'Missing path argument' };
      const absPath = path.isAbsolute(targetPath) ? targetPath : path.resolve(workspaceRoot, targetPath);

      if (!fs.existsSync(absPath)) {
        return { error: `File "${targetPath}" does not exist in workspace.` };
      }

      const stat = fs.statSync(absPath);
      if (stat.isDirectory()) {
        return { error: `"${targetPath}" is a directory. Use list_directory instead.` };
      }

      let content = fs.readFileSync(absPath, 'utf8');
      const lines = content.split(/\r?\n/);
      const totalLines = lines.length;

      if (args.startLine || args.endLine) {
        const start = Math.max(1, parseInt(args.startLine, 10) || 1);
        const end = Math.min(totalLines, parseInt(args.endLine, 10) || totalLines);
        const slice = lines.slice(start - 1, end);
        content = slice.join('\n');
        return {
          path: targetPath,
          content,
          startLine: start,
          endLine: end,
          totalLines,
        };
      }

      return {
        path: targetPath,
        content,
        totalLines,
        sizeBytes: stat.size,
      };
    },
  });

  // ── Filesystem: Write ───────────────────────────────────────────────────────
  registry.registerTool({
    name: 'write_file',
    description: 'Write complete new content to a file at the specified path. Creates parent directories if needed.',
    permission: PermissionLevels.WRITE,
    inputSchema: {
      type: 'object',
      properties: {
        path: {
          type: 'string',
          description: 'Relative path to the file within the workspace',
        },
        content: {
          type: 'string',
          description: 'The full updated code or content to write to the file',
        },
      },
      required: ['path', 'content'],
    },
    execute: async ({ args, workspaceRoot }) => {
      const targetPath = args.path;
      const content = args.content ?? '';
      if (!targetPath) return { error: 'Missing path argument' };

      const absPath = path.isAbsolute(targetPath) ? targetPath : path.resolve(workspaceRoot, targetPath);
      const dir = path.dirname(absPath);
      if (!fs.existsSync(dir)) {
        fs.mkdirSync(dir, { recursive: true });
      }

      let previousContent = '';
      if (fs.existsSync(absPath)) {
        previousContent = fs.readFileSync(absPath, 'utf8');
      }

      fs.writeFileSync(absPath, content, 'utf8');
      return {
        path: targetPath,
        success: true,
        bytesWritten: Buffer.byteLength(content, 'utf8'),
        previousContent: previousContent.substring(0, 500),
      };
    },
  });

  // ── Filesystem: Create ─────────────────────────────────────────────────────
  registry.registerTool({
    name: 'create_file',
    description: 'Create a new empty file or new folder in the workspace.',
    permission: PermissionLevels.WRITE,
    inputSchema: {
      type: 'object',
      properties: {
        path: {
          type: 'string',
          description: 'Relative path for the new file or directory',
        },
        isDirectory: {
          type: 'boolean',
          description: 'Whether to create a directory instead of a file (default: false)',
        },
      },
      required: ['path'],
    },
    execute: async ({ args, workspaceRoot }) => {
      const targetPath = args.path;
      if (!targetPath) return { error: 'Missing path argument' };
      const absPath = path.isAbsolute(targetPath) ? targetPath : path.resolve(workspaceRoot, targetPath);

      if (args.isDirectory) {
        fs.mkdirSync(absPath, { recursive: true });
        return { path: targetPath, isDirectory: true, created: true };
      } else {
        const dir = path.dirname(absPath);
        if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
        if (!fs.existsSync(absPath)) fs.writeFileSync(absPath, '', 'utf8');
        return { path: targetPath, created: true };
      }
    },
  });

  // ── Filesystem: Delete ─────────────────────────────────────────────────────
  registry.registerTool({
    name: 'delete_file',
    description: 'Delete a file or folder from the workspace. Use with caution.',
    permission: PermissionLevels.DESTRUCTIVE,
    inputSchema: {
      type: 'object',
      properties: {
        path: {
          type: 'string',
          description: 'Relative path of the file or folder to delete',
        },
      },
      required: ['path'],
    },
    execute: async ({ args, workspaceRoot }) => {
      const targetPath = args.path;
      if (!targetPath) return { error: 'Missing path argument' };
      const absPath = path.isAbsolute(targetPath) ? targetPath : path.resolve(workspaceRoot, targetPath);

      if (!fs.existsSync(absPath)) {
        return { path: targetPath, deleted: false, message: 'File did not exist' };
      }

      const stat = fs.statSync(absPath);
      if (stat.isDirectory()) {
        fs.rmSync(absPath, { recursive: true, force: true });
      } else {
        fs.unlinkSync(absPath);
      }

      return { path: targetPath, deleted: true };
    },
  });

  // ── Filesystem: List Directory ─────────────────────────────────────────────
  registry.registerTool({
    name: 'list_directory',
    description: 'List the files and directories inside a workspace folder.',
    permission: PermissionLevels.READ,
    inputSchema: {
      type: 'object',
      properties: {
        path: {
          type: 'string',
          description: 'Relative path to list (default: "" for workspace root)',
        },
      },
    },
    execute: async ({ args, workspaceRoot }) => {
      const targetPath = args.path || '';
      const absPath = path.isAbsolute(targetPath) ? targetPath : path.resolve(workspaceRoot, targetPath);

      if (!fs.existsSync(absPath)) {
        return { error: `Directory "${targetPath}" does not exist` };
      }

      const entries = fs.readdirSync(absPath, { withFileTypes: true });
      const items = entries.map((entry) => ({
        name: entry.name,
        isDirectory: entry.isDirectory(),
        path: path.relative(workspaceRoot, path.join(absPath, entry.name)).replace(/\\/g, '/'),
      }));

      return { path: targetPath, items };
    },
  });

  // ── Search: Code Search (Ripgrep) ──────────────────────────────────────────
  registry.registerTool({
    name: 'search_code',
    description: 'Search for text, symbols, or regex patterns across the codebase using fast ripgrep.',
    permission: PermissionLevels.READ,
    inputSchema: {
      type: 'object',
      properties: {
        query: {
          type: 'string',
          description: 'The search query or pattern',
        },
        caseSensitive: {
          type: 'boolean',
          description: 'Whether search is case-sensitive (default: false)',
        },
        filePattern: {
          type: 'string',
          description: 'Optional glob pattern to restrict search (e.g. "*.dart", "*.js")',
        },
      },
      required: ['query'],
    },
    execute: async ({ args, workspaceRoot }) => {
      return new Promise((resolve) => {
        searchModule.searchCode(
          args.query,
          workspaceRoot,
          {
            caseSensitive: !!args.caseSensitive,
            filePattern: args.filePattern,
            maxResults: 50,
          },
          (err, results) => {
            if (err) return resolve({ error: err.message });
            resolve({ query: args.query, matchesCount: results.length, matches: results });
          }
        );
      });
    },
  });

  // ── Search: Find Files by Pattern ──────────────────────────────────────────
  registry.registerTool({
    name: 'find_files',
    description: 'Find files in the workspace matching a name or pattern (e.g. "settings", "*.dart").',
    permission: PermissionLevels.READ,
    inputSchema: {
      type: 'object',
      properties: {
        pattern: {
          type: 'string',
          description: 'File name pattern or substring to search for',
        },
      },
      required: ['pattern'],
    },
    execute: async ({ args, workspaceRoot }) => {
      return new Promise((resolve) => {
        searchModule.findFiles(args.pattern, workspaceRoot, (err, files) => {
          if (err) return resolve({ error: err.message });
          resolve({ pattern: args.pattern, matches: files });
        });
      });
    },
  });

  // ── Terminal: Execute Command ──────────────────────────────────────────────
  registry.registerTool({
    name: 'run_terminal_command',
    description: 'Execute a shell command in the workspace directory (e.g. "npm test", "flutter analyze", "git status"). Observe output and exit code.',
    permission: PermissionLevels.EXECUTE,
    inputSchema: {
      type: 'object',
      properties: {
        command: {
          type: 'string',
          description: 'The command to execute',
        },
        timeoutMs: {
          type: 'integer',
          description: 'Optional timeout in milliseconds (default: 30000)',
        },
      },
      required: ['command'],
    },
    execute: async ({ args, workspaceRoot, cancellationToken }) => {
      return new Promise((resolve) => {
        const cmd = args.command;
        if (!cmd) return resolve({ error: 'Missing command argument' });

        let finished = false;
        const proc = terminalModule.executeCommand(
          cmd,
          workspaceRoot,
          (err, stdout, stderr, exitCode) => {
            if (finished) return;
            finished = true;
            resolve({
              command: cmd,
              exitCode: exitCode ?? (err ? 1 : 0),
              stdout: stdout || '',
              stderr: stderr || '',
              error: err ? err.message : null,
            });
          }
        );

        if (cancellationToken) {
          cancellationToken.onCancelled(() => {
            if (!finished && proc) {
              finished = true;
              terminalModule.killProcess(proc);
              resolve({ command: cmd, cancelled: true, exitCode: -1 });
            }
          });
        }
      });
    },
  });

  // ── Git: Status ────────────────────────────────────────────────────────────
  registry.registerTool({
    name: 'git_status',
    description: 'Get the current Git branch and list of modified/staged/untracked files.',
    permission: PermissionLevels.READ,
    inputSchema: {
      type: 'object',
      properties: {},
    },
    execute: async ({ workspaceRoot }) => {
      return new Promise((resolve) => {
        gitModule.getGitStatus(workspaceRoot, (err, status) => {
          if (err) return resolve({ error: err.message });
          resolve(status);
        });
      });
    },
  });

  // ── Git: Diff ──────────────────────────────────────────────────────────────
  registry.registerTool({
    name: 'git_diff',
    description: 'Get the Git diff for working tree or staged changes.',
    permission: PermissionLevels.READ,
    inputSchema: {
      type: 'object',
      properties: {
        path: {
          type: 'string',
          description: 'Optional relative file path to diff',
        },
        staged: {
          type: 'boolean',
          description: 'Whether to show staged diff (default: false)',
        },
      },
    },
    execute: async ({ args, workspaceRoot }) => {
      return new Promise((resolve) => {
        gitModule.getGitDiff(workspaceRoot, args.path, !!args.staged, (err, diff) => {
          if (err) return resolve({ error: err.message });
          resolve({ diff });
        });
      });
    },
  });

  // ── Context: Project Info ──────────────────────────────────────────────────
  registry.registerTool({
    name: 'get_project_info',
    description: 'Get high-level information about the workspace project (project name, manifests, tech stack).',
    permission: PermissionLevels.READ,
    inputSchema: {
      type: 'object',
      properties: {},
    },
    execute: async ({ workspaceRoot }) => {
      const projectName = path.basename(workspaceRoot);
      const manifests = [];
      if (fs.existsSync(path.join(workspaceRoot, 'pubspec.yaml'))) manifests.push('pubspec.yaml (Flutter/Dart)');
      if (fs.existsSync(path.join(workspaceRoot, 'package.json'))) manifests.push('package.json (Node/JS)');
      if (fs.existsSync(path.join(workspaceRoot, 'Cargo.toml'))) manifests.push('Cargo.toml (Rust)');
      if (fs.existsSync(path.join(workspaceRoot, 'go.mod'))) manifests.push('go.mod (Go)');
      if (fs.existsSync(path.join(workspaceRoot, 'requirements.txt'))) manifests.push('requirements.txt (Python)');

      return {
        projectName,
        root: workspaceRoot,
        manifests,
        hasGit: fs.existsSync(path.join(workspaceRoot, '.git')),
      };
    },
  });
}

module.exports = {
  registerIdeTools,
};
