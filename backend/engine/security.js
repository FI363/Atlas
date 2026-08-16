const LOOPBACK_HOSTS = new Set(['127.0.0.1', '::1', 'localhost']);

function isLoopbackHost(host) {
  return LOOPBACK_HOSTS.has(String(host || '').trim().toLowerCase());
}

function validateEngineConfig({ host, token }) {
  const normalizedHost = String(host || '').trim();
  const normalizedToken = String(token || '').trim();

  if (!normalizedHost) {
    throw new Error('ATLAS_ENGINE_HOST must not be empty.');
  }
  if (!normalizedToken) {
    throw new Error(
      'ATLAS_ENGINE_TOKEN is required. Start Atlas with `npm run dev` or set a strong token explicitly.'
    );
  }
  if (!isLoopbackHost(normalizedHost) && normalizedToken.length < 16) {
    throw new Error(
      'A network-accessible engine requires an ATLAS_ENGINE_TOKEN of at least 16 characters.'
    );
  }

  return { host: normalizedHost, token: normalizedToken };
}

module.exports = { isLoopbackHost, validateEngineConfig };
