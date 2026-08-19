const assert = require('assert');
const { ProviderManager } = require('../engine/providers/provider_manager');
const { GeminiProvider } = require('../engine/providers/gemini_provider');
const { ClaudeProvider } = require('../engine/providers/claude_provider');
const { OpenAIProvider } = require('../engine/providers/openai_provider');
const { OpenRouterProvider } = require('../engine/providers/openrouter_provider');
const { LocalProvider } = require('../engine/providers/local_provider');
const { RemoteProvider } = require('../engine/providers/remote_provider');

async function runProviderTests() {
  console.log('--- Running Model Provider Unit Tests ---');

  const manager = new ProviderManager();
  manager.registerProvider('gemini', GeminiProvider);
  manager.registerProvider('claude', ClaudeProvider);
  manager.registerProvider('openai', OpenAIProvider);
  manager.registerProvider('openrouter', OpenRouterProvider);
  manager.registerProvider('local', LocalProvider);
  manager.registerProvider('remote', RemoteProvider);

  // 1. List providers
  const providers = manager.listProviders();
  assert.strictEqual(providers.length, 6);
  console.log('✓ ProviderManager lists all 6 registered providers');

  // 2. Gemini Provider formatting tests
  const gemini = manager.getProvider('gemini', { apiKey: 'dummy-key' });
  assert.strictEqual(gemini.id, 'gemini');
  assert.strictEqual(gemini.name, 'Google Gemini');

  const testMessages = [
    { role: 'system', content: 'You are Atlas coding assistant.' },
    { role: 'user', content: 'Inspect the code' },
    {
      role: 'assistant',
      content: 'I will read the file.',
      tool_calls: [
        {
          id: 'call_1',
          function: { name: 'read_file', arguments: JSON.stringify({ path: 'main.dart' }) },
        },
      ],
    },
    {
      role: 'tool',
      name: 'read_file',
      tool_call_id: 'call_1',
      content: JSON.stringify({ content: 'void main() {}' }),
    },
  ];

  const testTools = [
    {
      type: 'function',
      function: {
        name: 'read_file',
        description: 'Read file',
        parameters: { type: 'object', properties: { path: { type: 'string' } } },
      },
    },
  ];

  const { systemText, contents } = gemini._formatContents(testMessages);
  assert.strictEqual(systemText, 'You are Atlas coding assistant.');
  assert.strictEqual(contents.length, 3);
  assert.strictEqual(contents[0].role, 'user');
  assert.strictEqual(contents[1].role, 'model');
  assert.strictEqual(contents[1].parts[1].functionCall.name, 'read_file');
  assert.strictEqual(contents[2].parts[0].functionResponse.name, 'read_file');
  console.log('✓ GeminiProvider correctly formats multi-turn messages and functionCalls/functionResponses');

  const geminiTools = gemini._formatTools(testTools);
  assert.strictEqual(geminiTools[0].functionDeclarations[0].name, 'read_file');
  console.log('✓ GeminiProvider correctly formats functionDeclarations');

  // 3. Claude Provider formatting tests
  const claude = manager.getProvider('claude', { apiKey: 'dummy-key' });
  const claudeFormatted = claude._formatMessages(testMessages);
  assert.strictEqual(claudeFormatted.system, 'You are Atlas coding assistant.');
  assert.strictEqual(claudeFormatted.messages[1].role, 'assistant');
  assert.strictEqual(claudeFormatted.messages[1].content[1].type, 'tool_use');
  console.log('✓ ClaudeProvider correctly formats Anthropic Messages API tool_use and tool_result');

  console.log('✅ ALL MODEL PROVIDER TESTS PASSED!\n');
}

runProviderTests().catch((err) => {
  console.error('❌ Provider Tests Failed:', err);
  process.exit(1);
});
