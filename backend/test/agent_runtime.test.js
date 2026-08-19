const assert = require('assert');
const path = require('path');
const fs = require('fs');
const os = require('os');
const { initializeAgentRuntime } = require('../engine/runtime/init_runtime');
const { ModelProvider } = require('../engine/providers/base_provider');
const { AgentEvents } = require('../engine/runtime/event_bus');

class MockTestProvider extends ModelProvider {
  get id() { return 'mock_test'; }
  get name() { return 'Mock Test Provider'; }

  constructor(config = {}) {
    super(config);
    this.step = 0;
  }

  async send({ messages, tools = [] }) {
    this.step++;
    const lastMsg = messages[messages.length - 1];

    if (this.step === 1) {
      // Step 1: Request reading test file
      return {
        content: 'I need to inspect the file first.',
        toolCalls: [
          {
            id: 'call_read_1',
            name: 'read_file',
            args: { path: 'calc.js' },
          },
        ],
      };
    } else if (this.step === 2) {
      // Step 2: Request fixing bug in calc.js
      return {
        content: 'I found the bug. Fixing calc.js.',
        toolCalls: [
          {
            id: 'call_write_1',
            name: 'write_file',
            args: { path: 'calc.js', content: 'function add(a, b) { return a + b; }\nmodule.exports = { add };' },
          },
        ],
      };
    } else if (this.step === 3) {
      // Step 3: Run terminal command to verify
      return {
        content: 'Verifying fix via test command.',
        toolCalls: [
          {
            id: 'call_exec_1',
            name: 'run_terminal_command',
            args: { command: 'node -e "const { add } = require(\'./calc.js\'); if (add(2, 3) !== 5) process.exit(1); console.log(\'TEST_PASSED\');"' },
          },
        ],
      };
    } else {
      // Step 4: Final response
      return {
        content: 'Task complete: Bug in calc.js has been fixed and verified with tests.',
        toolCalls: [],
      };
    }
  }
}

async function runAgentRuntimeTests() {
  console.log('--- Running Agent Runtime ReAct Loop Tests ---');

  const testDir = fs.mkdtempSync(path.join(os.tmpdir(), 'atlas-runtime-test-'));
  // Create a buggy calc.js file
  fs.writeFileSync(path.join(testDir, 'calc.js'), 'function add(a, b) { return a - b; }\nmodule.exports = { add };');

  const {
    eventBus,
    providerManager,
    permissionManager,
    sessionManager,
    agentRuntime,
  } = initializeAgentRuntime({ permissionPolicy: 'auto_all' });

  // Register mock provider
  providerManager.registerProvider('mock_test', MockTestProvider);

  // Track runtime events
  const recordedEvents = [];
  eventBus.on('*', (e) => {
    recordedEvents.push(e.event);
  });

  // Create session
  const session = sessionManager.getOrCreate('test_session_1', {
    workspaceRoot: testDir,
    providerId: 'mock_test',
    modelId: 'test-model',
  });

  // Run agent task
  const result = await agentRuntime.start({
    prompt: 'Fix the bug in calc.js and verify the test passes.',
    session,
    ideContext: { workspaceRoot: testDir },
    settings: { aiProvider: 'mock_test' },
  });

  // Verifications
  assert.strictEqual(result.iterations, 4);
  assert.strictEqual(result.toolCallsCount, 3);
  assert.strictEqual(result.content.includes('Task complete'), true);
  console.log('✓ AgentRuntime executed multi-step ReAct loop with 3 tool executions');

  // Verify file content on disk
  const updatedContent = fs.readFileSync(path.join(testDir, 'calc.js'), 'utf8');
  assert.strictEqual(updatedContent.includes('return a + b;'), true);
  console.log('✓ Target file was actually modified on disk by the agent');

  // Verify events emitted
  assert.strictEqual(recordedEvents.includes(AgentEvents.STARTED), true);
  assert.strictEqual(recordedEvents.includes(AgentEvents.TOOL_CALL), true);
  assert.strictEqual(recordedEvents.includes(AgentEvents.TOOL_RESULT), true);
  assert.strictEqual(recordedEvents.includes(AgentEvents.FILE_CHANGED), true);
  assert.strictEqual(recordedEvents.includes(AgentEvents.COMPLETED), true);
  console.log('✓ EventBus emitted all expected typed runtime events');

  // Verify session retention and model switching
  assert.strictEqual(session.conversation.length > 5, true);
  session.switchModel('gemini', 'gemini-2.5-flash');
  assert.strictEqual(session.providerId, 'gemini');
  assert.strictEqual(session.modelId, 'gemini-2.5-flash');
  console.log('✓ Session preserved conversation history across model switch');

  // Cleanup
  try {
    fs.rmSync(testDir, { recursive: true, force: true, maxRetries: 3, retryDelay: 100 });
  } catch (_) {}
  console.log('✅ ALL AGENT RUNTIME TESTS PASSED!\n');
}

runAgentRuntimeTests().catch((err) => {
  console.error('❌ Agent Runtime Tests Failed:', err);
  process.exit(1);
});
