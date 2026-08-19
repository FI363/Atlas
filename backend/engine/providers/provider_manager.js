const { ModelProvider } = require('./base_provider');

/**
 * Manages registration, lookup, and configuration of model providers.
 */
class ProviderManager {
  constructor() {
    /** @type {Map<string, typeof ModelProvider>} */
    this._providerClasses = new Map();
    /** @type {Map<string, ModelProvider>} */
    this._activeInstances = new Map();
  }

  /**
   * Register a provider class.
   * @param {string} id Unique provider ID
   * @param {typeof ModelProvider} ProviderClass Class extending ModelProvider
   */
  registerProvider(id, ProviderClass) {
    this._providerClasses.set(id, ProviderClass);
    // Invalidate any existing instance so new config applies
    this._activeInstances.delete(id);
  }

  /**
   * Get or create a provider instance with given settings.
   * @param {string} id Provider identifier
   * @param {object} [config={}] Provider specific configuration
   * @returns {ModelProvider}
   */
  getProvider(id, config = {}) {
    const ProviderClass = this._providerClasses.get(id);
    if (!ProviderClass) {
      const available = Array.from(this._providerClasses.keys()).join(', ');
      throw new Error(`Model provider "${id}" is not registered. Available providers: [${available}]`);
    }

    return new ProviderClass(config);
  }

  /**
   * List all registered providers and their metadata.
   * @returns {Array<{ id: string, name: string, models: string[], capabilities: object }>}
   */
  listProviders() {
    const result = [];
    for (const [id, ProviderClass] of this._providerClasses) {
      try {
        const instance = new ProviderClass({});
        result.push({
          id: instance.id,
          name: instance.name,
          models: instance.models,
          capabilities: instance.capabilities,
        });
      } catch (_) {
        result.push({ id, name: id, models: [], capabilities: {} });
      }
    }
    return result;
  }
}

module.exports = {
  ProviderManager,
};
