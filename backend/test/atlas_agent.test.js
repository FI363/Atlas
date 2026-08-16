const assert = require('assert');
const path = require('path');
const fs = require('fs');

// Import engine modules
const settingsModule = require('../engine/settings');
const workspaceModule = require('../engine/workspace');
const filesystemModule = require('../engine/filesystem');
const searchModule = require('../engine/search');
const gitModule = require('../engine/git');
const terminalModule = require('../engine/terminal');
const { PermissionManager, PERMISSION_CATEGORIES } = require('../engine/permissions');
const { initializeMcpTools, globalRegistry } = require('../engine/mcp/init');
const { buildAgentSystemPrompt } = require('../engine/agent/context_builder');
const { generateUnifiedDiff } = require('../engine/agent/diff_engine');
const { AgentLoop } = require('../engine/agent/agent_loop');

async function runTests() {
  console.log('--- Running Atlas Engine & MCP Unit Tests ---');
  const testDir = workspaceModule.DEFAULT_PROJECT_ROOT;

  // 1. Test MCP Registry Initialization
  initializeMcpTools();
  const tools = globalRegistry.listTools();
  assert(tools.length >= 10, `Expected at least 10 MCP tools, got ${tools.length}`);
  console.log(`✓ MCP Tool Registry initialized with ${tools.length} tools`);

  // 2. Test Permission Manager
  const permMgr = new PermissionManager('approve_write');
  const readCheck = permMgr.checkPermission('read_file', { path: 'pubspec.yaml' });
  assert.strictEqual(readCheck.allowed, true, 'READ operations should be auto-approved under approve_write policy');
  assert.strictEqual(readCheck.category, PERMISSION_CATEGORIES.READ);

  const writeCheck = permMgr.checkPermission('write_file', { path: 'temp.txt' });
  assert.strictEqual(writeCheck.allowed, false, 'WRITE operations should require approval under approve_write policy');
  assert.strictEqual(writeCheck.requiresApproval, true);
  console.log('✓ PermissionManager policy checks passed');

  // 3. Test Filesystem Tools
  const tree = filesystemModule.buildTree(testDir);
  assert(Array.isArray(tree), 'buildTree should return array');
  console.log(`✓ Filesystem buildTree returned ${tree.length} top-level items`);

  // 4. Test Search Tools
  const searchResults = searchModule.searchWorkspaceFiles(testDir, testDir, 'Atlas', [], 5);
  assert(Array.isArray(searchResults), 'searchWorkspaceFiles should return array');
  console.log(`✓ Search found ${searchResults.length} matches for "Atlas"`);

  // 5. Test Diff Engine
  const diffResult = generateUnifiedDiff('test.txt', 'hello\nworld', 'hello\natlas\nworld');
  assert.strictEqual(diffResult.hasChanges, true, 'Diff engine should detect changes');
  assert(diffResult.diff.includes('+atlas'), 'Diff text should contain added line +atlas');
  console.log('✓ Unified Diff Engine generated diff successfully');

  // 6. Test Context Builder
  const systemPrompt = buildAgentSystemPrompt({
    projectName: 'atlas',
    activeFile: 'lib/main.dart',
    cursor: { line: 10, column: 5 },
  });
  assert(systemPrompt.includes('lib/main.dart'), 'System prompt should include active file');
  console.log('✓ Agent Context Builder constructed prompt');

  // 7. Test Agent Loop (Mock Run)
  const agentLoop = new AgentLoop({
    workspaceRoot: testDir,
    permissionManager: permMgr,
    toolRegistry: globalRegistry,
    settings: { aiProvider: 'builtIn' },
    callbacks: {},
  });
  const res = await agentLoop.run('find authentication', { activeFile: 'lib/main.dart' });
  assert(res && res.content, 'Agent loop should return a response content');
  console.log('✓ Agent Loop completed execution cycle');

  console.log('\n✅ ALL ATLAS ENGINE & MCP TESTS PASSED SUCCESSFULY!\n');
}

runTests().catch((err) => {
  console.error('❌ Test failed:', err);
  process.exit(1);
});
