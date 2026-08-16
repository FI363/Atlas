const assert = require('assert');
const { isLoopbackHost, validateEngineConfig } = require('../engine/security');

assert.strictEqual(isLoopbackHost('127.0.0.1'), true);
assert.strictEqual(isLoopbackHost('localhost'), true);
assert.strictEqual(isLoopbackHost('0.0.0.0'), false);

assert.throws(
  () => validateEngineConfig({ host: '127.0.0.1', token: '' }),
  /ATLAS_ENGINE_TOKEN is required/
);
assert.throws(
  () => validateEngineConfig({ host: '0.0.0.0', token: 'short' }),
  /at least 16 characters/
);
assert.deepStrictEqual(
  validateEngineConfig({ host: '0.0.0.0', token: 'a-secure-token-value' }),
  { host: '0.0.0.0', token: 'a-secure-token-value' }
);

console.log('Security configuration tests passed.');
