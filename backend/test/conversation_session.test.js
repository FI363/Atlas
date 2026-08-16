const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');

const { AgentLoop } = require('../engine/agent/agent_loop');
const { ConversationSessionStore } = require('../engine/agent/conversation_session');
const { PermissionManager } = require('../engine/permissions');
const { initializeMcpTools, globalRegistry } = require('../engine/mcp/init');

function makeLoop(session, workspaceRoot) {
  return new AgentLoop({
    workspaceRoot,
    permissionManager: new PermissionManager('auto_all'),
    toolRegistry: globalRegistry,
    settings: { aiProvider: 'builtIn' },
    conversation: session.conversation,
    callbacks: {},
  });
}

async function runTests() {
  console.log('--- Running Atlas Conversation Session Tests ---');
  initializeMcpTools();

  const workspaceRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'atlas-conversation-'));
  try {
    const store = new ConversationSessionStore();
    const session = store.getOrCreate('atlas_test_session_001', workspaceRoot);
    assert.strictEqual(store.getOrCreate('atlas_test_session_001', workspaceRoot), session);

    // Test A: clarification then a follow-up must use the same transcript and
    // execute its MCP filesystem tool rather than start with a new greeting.
    const first = await makeLoop(session, workspaceRoot).run(
      'create a text file in my current directory',
      { projectName: 'conversation-test', cwd: workspaceRoot },
    );
    assert.match(first.content, /what would you like to name/i);
    assert.strictEqual(session.conversation.filter((m) => m.role === 'system').length, 1);

    const second = await makeLoop(session, workspaceRoot).run(
      'anything you want',
      { projectName: 'conversation-test', cwd: workspaceRoot },
    );
    const createdFile = path.join(workspaceRoot, 'atlas-note.txt');
    assert.strictEqual(fs.existsSync(createdFile), true, 'The follow-up should create the requested file');
    assert.match(second.content, /task complete/i);

    // Test B: a third turn operates on the file established by the two prior
    // turns, proving the agent has preserved the ongoing conversation.
    await makeLoop(session, workspaceRoot).run(
      'change the content to hello from the third turn',
      { projectName: 'conversation-test', cwd: workspaceRoot },
    );
    assert.strictEqual(fs.readFileSync(createdFile, 'utf8'), 'hello from the third turn');
    assert.deepStrictEqual(
      session.conversation.filter((m) => m.role === 'user').map((m) => m.content),
      [
        'create a text file in my current directory',
        'anything you want',
        'change the content to hello from the third turn',
      ],
    );
    assert.strictEqual(session.conversation.filter((m) => m.role === 'system').length, 1);
    assert(session.conversation.some((m) => m.role === 'tool'), 'MCP tool results should be retained in the session transcript');
    console.log('✓ Multi-turn conversation and MCP tool context persisted');

    // Test D/E: a failed tool call remains in history and a following turn can
    // continue normally without replacing the conversation with a new agent.
    const errorSession = store.getOrCreate('atlas_test_session_002', workspaceRoot);
    await makeLoop(errorSession, workspaceRoot).run(
      'delete file missing-file.txt',
      { projectName: 'conversation-test', cwd: workspaceRoot },
    );
    assert(
      errorSession.conversation.some((m) => m.role === 'tool' && String(m.content).includes('Path not found: missing-file.txt')),
      'The failed tool result should be recorded in the conversation',
    );

    const recovery = await makeLoop(errorSession, workspaceRoot).run(
      'find atlas-note',
      { projectName: 'conversation-test', cwd: workspaceRoot },
    );
    assert.match(recovery.content, /task complete/i);
    assert.strictEqual(errorSession.conversation.filter((m) => m.role === 'system').length, 1);
    assert.deepStrictEqual(
      errorSession.conversation.filter((m) => m.role === 'user').map((m) => m.content),
      ['delete file missing-file.txt', 'find atlas-note'],
    );
    console.log('✓ Tool failure surfaced and subsequent turn retained context');
  } finally {
    fs.rmSync(workspaceRoot, { recursive: true, force: true });
  }

  console.log('Conversation session tests passed.');
}

runTests().catch((error) => {
  console.error('Conversation session test failed:', error);
  process.exit(1);
});
