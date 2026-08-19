'use strict';
// ─────────────────────────────────────────────────────────────────────────────
// CancellationToken — lightweight cancellation signal propagated into tools.
// ─────────────────────────────────────────────────────────────────────────────

class CancellationToken {
  constructor() {
    this.cancelled = false;
    this.callbacks = [];
  }

  cancel() {
    this.cancelled = true;
    for (const cb of this.callbacks) {
      cb();
    }
    this.callbacks = [];
  }

  onCancelled(cb) {
    if (this.cancelled) {
      cb();
    } else {
      this.callbacks.push(cb);
    }
  }

  /** Throws if the token has been cancelled. Use inside long-running loops. */
  throwIfCancelled() {
    if (this.cancelled) {
      const err = new Error('Operation was cancelled');
      err.code = 'ECANCELLED';
      throw err;
    }
  }

  /** Returns a promise that rejects when the token is cancelled. */
  raceWith(promise) {
    if (this.cancelled) return Promise.reject(new Error('Operation was cancelled'));
    return promise;
  }
}

module.exports = { CancellationToken };
