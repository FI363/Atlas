const assert = require('assert');
const path = require('path');
const fs = require('fs');
const os = require('os');
const { ToolRegistry } = require('../engine/tools/tool_registry');
const { registerIdeTools } = require('../engine/tools/ide_tool_adapter');
const { PermissionLevels } = require('../engine/permissions/permission_manager');

async function runToolTests() {
  console.log('--- Running IDE Tool Adapter Unit Tests ---');

  const testDir = fs.mkdtempSync(path.join(os.tmpdir(), 'atlas-tool-test-'));
  const registry = new ToolRegistry();
  registerIdeTools(registry);

  // 1. Verify all expected tools registered
  const expectedTools = [
    'read_file',
    'write_file',
    'create_file',
    'delete_file',
    'list_directory',
    'search_code',
    'find_files',
    'run_terminal_command',
    'git_status',
    'git_diff',
    'get_project_info',
  ];

  for (const name of expectedTools) {
    assert.strictEqual(registry.hasTool(name), true, `Expected tool "${name}" to be registered`);
  }
  console.log(`✓ All ${expectedTools.length} native IDE tools registered in ToolRegistry`);

  // 2. Test write_file & read_file
  const testFileRel = 'test_sample.txt';
  const initialContent = 'Hello Atlas Agent Runtime\nLine 2: Target line\nLine 3: End';

  const writeResult = await registry.executeTool('write_file', {
    path: testFileRel,
    content: initialContent,
  }, { workspaceRoot: testDir });

  assert.strictEqual(writeResult.success, true);
  assert.strictEqual(fs.existsSync(path.join(testDir, testFileRel)), true);
  console.log('✓ write_file creates file and parent folders successfully');

  const readResult = await registry.executeTool('read_file', {
    path: testFileRel,
  }, { workspaceRoot: testDir });

  assert.strictEqual(readResult.content, initialContent);
  assert.strictEqual(readResult.totalLines, 3);
  console.log('✓ read_file reads complete contents with line metrics');

  // Sliced read
  const sliceResult = await registry.executeTool('read_file', {
    path: testFileRel,
    startLine: 2,
    endLine: 2,
  }, { workspaceRoot: testDir });
  assert.strictEqual(sliceResult.content, 'Line 2: Target line');
  console.log('✓ read_file slices lines accurately');

  // 3. Test list_directory
  const listResult = await registry.executeTool('list_directory', {}, { workspaceRoot: testDir });
  assert.strictEqual(Array.isArray(listResult.items), true);
  assert.strictEqual(listResult.items.some((i) => i.name === testFileRel), true);
  console.log('✓ list_directory lists entries in workspace');

  // 4. Test run_terminal_command
  const termResult = await registry.executeTool('run_terminal_command', {
    command: 'node -e "console.log(123 + 456)"',
  }, { workspaceRoot: testDir });

  assert.strictEqual(termResult.exitCode, 0);
  assert.strictEqual(termResult.stdout.trim(), '579');
  console.log('✓ run_terminal_command executes process and returns stdout/exitCode');

  // 5. Test delete_file
  const delResult = await registry.executeTool('delete_file', {
    path: testFileRel,
  }, { workspaceRoot: testDir });

  assert.strictEqual(delResult.deleted, true);
  assert.strictEqual(fs.existsSync(path.join(testDir, testFileRel)), false);
  console.log('✓ delete_file removes file from disk');

  // Cleanup temp dir
  fs.rmSync(testDir, { recursive: true, force: true });
  console.log('✅ ALL IDE TOOL ADAPTER TESTS PASSED!\n');
}

runToolTests().catch((err) => {
  console.error('❌ Tool Tests Failed:', err);
  process.exit(1);
});
