const terminal = require('../../terminal');

function registerExecutionTools(registry) {
  registry.registerTool({
    name: 'run_command',
    description: 'Execute a shell command in the project root.',
    inputSchema: {
      type: 'object',
      properties: {
        command: { type: 'string', description: 'Command line string to execute' },
        timeoutMs: { type: 'number', description: 'Timeout in ms (default: 60000)' },
      },
      required: ['command'],
    },
    async execute(args, context) {
      const result = await terminal.runCommandPromise(
        args.command,
        context.workspaceRoot,
        args.timeoutMs || 60000
      );
      return result;
    },
  });

  registry.registerTool({
    name: 'run_tests',
    description: 'Run project tests (autodetects Flutter/Node/Dart test commands).',
    inputSchema: {
      type: 'object',
      properties: {
        testCommand: { type: 'string', description: 'Custom test command if needed (e.g. "flutter test" or "npm test")' },
      },
      required: [],
    },
    async execute(args, context) {
      let command = args.testCommand;
      if (!command) {
        // Auto-detect project type
        const fs = require('fs');
        const path = require('path');
        const pubspecPath = path.join(context.workspaceRoot, 'pubspec.yaml');
        const packageJsonPath = path.join(context.workspaceRoot, 'package.json');

        if (fs.existsSync(pubspecPath)) {
          command = 'flutter test';
        } else if (fs.existsSync(packageJsonPath)) {
          command = 'npm test';
        } else {
          command = 'flutter test';
        }
      }

      const result = await terminal.runCommandPromise(command, context.workspaceRoot, 120000);
      return { commandExecuted: command, ...result };
    },
  });

  registry.registerTool({
    name: 'run_build',
    description: 'Run project build (e.g. flutter build, npm run build).',
    inputSchema: {
      type: 'object',
      properties: {
        buildCommand: { type: 'string', description: 'Custom build command (optional)' },
      },
      required: [],
    },
    async execute(args, context) {
      let command = args.buildCommand;
      if (!command) {
        const fs = require('fs');
        const path = require('path');
        if (fs.existsSync(path.join(context.workspaceRoot, 'pubspec.yaml'))) {
          command = 'flutter analyze';
        } else if (fs.existsSync(path.join(context.workspaceRoot, 'package.json'))) {
          command = 'npm run build';
        } else {
          command = 'flutter analyze';
        }
      }

      const result = await terminal.runCommandPromise(command, context.workspaceRoot, 120000);
      return { commandExecuted: command, ...result };
    },
  });
}

module.exports = { registerExecutionTools };
