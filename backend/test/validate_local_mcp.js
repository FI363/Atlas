const assert = require('assert');
const path = require('path');
const fs = require('fs');

const { initializeMcpTools, globalRegistry } = require('../engine/mcp/init');
const { PermissionManager } = require('../engine/permissions');
const { AgentLoop } = require('../engine/agent/agent_loop');
const filesystem = require('../engine/filesystem');
const aiProviders = require('../engine/ai_providers');

async function runValidationTest() {
  console.log('====================================================');
  console.log('   Atlas Local MCP Agent Validation & Diagnostic    ');
  console.log('====================================================\n');

  // Initialize MCP tools & workspace
  initializeMcpTools();
  const workspaceRoot = path.resolve(__dirname, '../..');
  const permManager = new PermissionManager('auto_all'); // auto-approve for automated testing

  const testFileRel = 'test_mcp_validation.txt';
  const testFileAbs = path.join(workspaceRoot, testFileRel);

  // Clean up any leftover test file
  if (fs.existsSync(testFileAbs)) {
    fs.unlinkSync(testFileAbs);
  }

  console.log('[Test 1] Testing File Creation via Agent Loop...');

  let toolExecuted = [];
  const agent1 = new AgentLoop({
    workspaceRoot,
    permissionManager: permManager,
    toolRegistry: globalRegistry,
    settings: { aiProvider: 'builtIn' },
    callbacks: {
      onProgress: (msg) => console.log(`   [Progress] ${msg}`),
      onToolCall: (call) => {
        console.log(`   [Tool Call] ${call.toolName}`, call.args);
        toolExecuted.push(call.toolName);
      },
      onToolResult: (res) => console.log(`   [Tool Result] ${res.toolName}:`, JSON.stringify(res.result).substring(0, 100)),
    },
  });

  const res1 = await agent1.run(`Create file ${testFileRel} with content "Hello Atlas MCP Validation"`);
  console.log('   [Agent Final Response]:', res1.content.substring(0, 150));

  const fileExists1 = fs.existsSync(testFileAbs);
  console.log(`   --> File Created on Disk? ${fileExists1 ? '✅ YES' : '❌ NO'}`);

  if (fileExists1) {
    const fileContent = fs.readFileSync(testFileAbs, 'utf-8');
    console.log(`   --> File Content: "${fileContent}"`);
  }

  console.log('\n[Test 2] Testing File Deletion via Agent Loop...');

  const agent2 = new AgentLoop({
    workspaceRoot,
    permissionManager: permManager,
    toolRegistry: globalRegistry,
    settings: { aiProvider: 'builtIn' },
    callbacks: {
      onProgress: (msg) => console.log(`   [Progress] ${msg}`),
      onToolCall: (call) => {
        console.log(`   [Tool Call] ${call.toolName}`, call.args);
        toolExecuted.push(call.toolName);
      },
      onToolResult: (res) => console.log(`   [Tool Result] ${res.toolName}:`, JSON.stringify(res.result).substring(0, 100)),
    },
  });

  const res2 = await agent2.run(`Delete file ${testFileRel}`);
  console.log('   [Agent Final Response]:', res2.content.substring(0, 150));

  const fileExists2 = fs.existsSync(testFileAbs);
  console.log(`   --> File Deleted from Disk? ${!fileExists2 ? '✅ YES' : '❌ NO'}`);

  console.log('\n====================================================');
  console.log('                DIAGNOSTIC SUMMARY                   ');
  console.log('====================================================');
  console.log(`Total Tools Triggered: ${toolExecuted.length}`);
  console.log(`Tools Executed: [${toolExecuted.join(', ')}]`);
  console.log(`File Creation Test: ${fileExists1 ? 'PASSED' : 'FAILED'}`);
  console.log(`File Deletion Test: ${!fileExists2 ? 'PASSED' : 'FAILED'}`);
  console.log('====================================================\n');
}

runValidationTest().catch((err) => {
  console.error('Validation test crashed:', err);
  process.exit(1);
});
