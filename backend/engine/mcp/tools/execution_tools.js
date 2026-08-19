const terminal = require('../../terminal');

function registerExecutionTools(registry) {
  registry.registerTool({
    name: 'run_command',
    description: 'Execute a shell command in the project workspace root. Returns stdout, stderr, and exit code.',
    inputSchema: {
      type: 'object',
      properties: {
        command:   { type: 'string', description: 'Command line string to execute (e.g. "flutter analyze")' },
        timeoutMs: { type: 'number', description: 'Timeout in milliseconds (default: 60000, max: 300000)' },
      },
      required: ['command'],
    },
    async execute(args, context) {
      const timeout = Math.min(args.timeoutMs || 60000, 300000);
      const result = await terminal.runCommandPromise(args.command, context.workspaceRoot, timeout);
      return result;
    },
  });

  registry.registerTool({
    name: 'run_tests',
    description: [
      'Run the project test suite. Auto-detects the test command from the project type.',
      'Returns structured results: { passed, failed, errors: [{file, line, message}], output, commandExecuted }.',
      'If tests fail, inspect errors, fix the code, and call run_tests again.',
    ].join('\n'),
    inputSchema: {
      type: 'object',
      properties: {
        testFilter:  { type: 'string', description: 'Optional test name filter / pattern (e.g. "widget_test" or "--name MyTest")' },
        testCommand: { type: 'string', description: 'Override the full test command (e.g. "flutter test test/my_test.dart")' },
      },
      required: [],
    },
    async execute(args, context) {
      const fs   = require('fs');
      const path = require('path');

      let command = args.testCommand;
      if (!command) {
        const hasPubspec     = fs.existsSync(path.join(context.workspaceRoot, 'pubspec.yaml'));
        const hasPackageJson = fs.existsSync(path.join(context.workspaceRoot, 'package.json'));
        const hasCargoToml   = fs.existsSync(path.join(context.workspaceRoot, 'Cargo.toml'));
        const hasGoMod       = fs.existsSync(path.join(context.workspaceRoot, 'go.mod'));

        if (hasPubspec)     command = 'flutter test';
        else if (hasPackageJson) command = 'npm test';
        else if (hasCargoToml)   command = 'cargo test';
        else if (hasGoMod)       command = 'go test ./...';
        else                     command = 'flutter test';
      }

      if (args.testFilter && !args.testCommand) {
        command += ` ${args.testFilter}`;
      }

      const raw = await terminal.runCommandPromise(command, context.workspaceRoot, 180000);

      // Parse structured results from test output
      const structured = parseTestOutput(raw.output || raw.stdout || '');
      return { commandExecuted: command, ...raw, ...structured };
    },
  });

  registry.registerTool({
    name: 'get_diagnostics',
    description: 'Run static analysis / linting on the project and return structured diagnostics (errors, warnings, hints).',
    inputSchema: {
      type: 'object',
      properties: {
        analyzeCommand: { type: 'string', description: 'Override the analysis command (default: auto-detected)' },
      },
      required: [],
    },
    async execute(args, context) {
      const fs   = require('fs');
      const path = require('path');

      let command = args.analyzeCommand;
      if (!command) {
        const hasPubspec     = fs.existsSync(path.join(context.workspaceRoot, 'pubspec.yaml'));
        const hasPackageJson = fs.existsSync(path.join(context.workspaceRoot, 'package.json'));
        const hasTsConfig    = fs.existsSync(path.join(context.workspaceRoot, 'tsconfig.json'));
        const hasCargoToml   = fs.existsSync(path.join(context.workspaceRoot, 'Cargo.toml'));

        if (hasPubspec)         command = 'flutter analyze --no-pub';
        else if (hasTsConfig)   command = 'npx tsc --noEmit';
        else if (hasPackageJson) command = 'npm run lint --if-present';
        else if (hasCargoToml)   command = 'cargo clippy --message-format json';
        else                     command = 'flutter analyze --no-pub';
      }

      const raw = await terminal.runCommandPromise(command, context.workspaceRoot, 120000);
      const diagnostics = parseDiagnostics(raw.output || raw.stdout || '');
      return { commandExecuted: command, ...raw, diagnostics };
    },
  });

  registry.registerTool({
    name: 'run_build',
    description: 'Run project build or compile step. Returns build output and exit code.',
    inputSchema: {
      type: 'object',
      properties: {
        buildCommand: { type: 'string', description: 'Custom build command (optional, auto-detected if omitted)' },
      },
      required: [],
    },
    async execute(args, context) {
      const fs   = require('fs');
      const path = require('path');

      let command = args.buildCommand;
      if (!command) {
        if (fs.existsSync(path.join(context.workspaceRoot, 'pubspec.yaml'))) {
          command = 'flutter build apk --debug';
        } else if (fs.existsSync(path.join(context.workspaceRoot, 'package.json'))) {
          command = 'npm run build';
        } else {
          command = 'flutter build apk --debug';
        }
      }

      const result = await terminal.runCommandPromise(command, context.workspaceRoot, 300000);
      return { commandExecuted: command, ...result };
    },
  });
}

// ── Output parsers ─────────────────────────────────────────────────────────

/**
 * Parse flutter test / jest / cargo test output into a structured summary.
 */
function parseTestOutput(output) {
  const lines = output.split('\n');
  let passed = 0, failed = 0;
  const errors = [];

  for (const line of lines) {
    // Flutter test: "+N: ..." or "+N -M: ..."
    const flutterPassed = line.match(/^\+(\d+)/);
    const flutterFailed = line.match(/-(\d+)/);
    if (flutterPassed) passed = parseInt(flutterPassed[1], 10);
    if (flutterFailed) failed = parseInt(flutterFailed[1], 10);

    // Flutter/Dart failure detail: "path/to/test.dart:line:col: ..."
    const dartErr = line.match(/^([\w./\\-]+\.dart):(\d+):(\d+):\s*(.+)/);
    if (dartErr) {
      errors.push({ file: dartErr[1], line: parseInt(dartErr[2], 10), message: dartErr[4] });
    }

    // Jest: "FAIL" / "PASS"
    if (line.startsWith('FAIL ')) {
      failed = (failed || 0) + 1;
      errors.push({ file: line.replace('FAIL ', '').trim(), line: 0, message: 'Test suite failed' });
    }

    // Cargo test failure
    const cargoFail = line.match(/^test (\S+) \.\.\. FAILED/);
    if (cargoFail) {
      failed++;
      errors.push({ file: 'rust', line: 0, message: `Test failed: ${cargoFail[1]}` });
    }

    // Generic "X passed, Y failed"
    const summary = line.match(/(\d+) passed.*?(\d+) failed/i);
    if (summary) {
      passed = parseInt(summary[1], 10);
      failed = parseInt(summary[2], 10);
    }
  }

  return { passed, failed, errors: errors.slice(0, 20) };
}

/**
 * Parse flutter analyze / tsc output into a structured diagnostics list.
 */
function parseDiagnostics(output) {
  const diagnostics = [];
  const lines = output.split('\n');

  for (const line of lines) {
    // flutter analyze: "  • message • path/file.dart:line:col • hint_code"
    const flutterDiag = line.match(/^\s+[•·]\s+(.+?)\s+[•·]\s+([\w./\\-]+):(\d+):(\d+)\s+[•·]/);
    if (flutterDiag) {
      diagnostics.push({
        message:  flutterDiag[1].trim(),
        file:     flutterDiag[2],
        line:     parseInt(flutterDiag[3], 10),
        column:   parseInt(flutterDiag[4], 10),
        severity: 'info',
      });
      continue;
    }

    // TypeScript: "path/file.ts(line,col): error TSxxxx: message"
    const tsDiag = line.match(/^([\w./\\-]+)\((\d+),(\d+)\):\s+(error|warning)\s+(\w+):\s+(.+)/);
    if (tsDiag) {
      diagnostics.push({
        file:     tsDiag[1],
        line:     parseInt(tsDiag[2], 10),
        column:   parseInt(tsDiag[3], 10),
        severity: tsDiag[4],
        code:     tsDiag[5],
        message:  tsDiag[6],
      });
    }
  }

  return diagnostics.slice(0, 50);
}

module.exports = { registerExecutionTools };
