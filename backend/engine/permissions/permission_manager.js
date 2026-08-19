const PermissionLevels = {
  READ: 'READ',
  WRITE: 'WRITE',
  EXECUTE: 'EXECUTE',
  DESTRUCTIVE: 'DESTRUCTIVE',
};

const PermissionPolicies = {
  AUTO_ALL: 'auto_all',
  APPROVE_WRITE: 'approve_write',
  APPROVE_ALL: 'approve_all',
  NEVER_ALLOW: 'never_allow',
};

class PermissionManager {
  /**
   * @param {string} policy Initial policy
   */
  constructor(policy = PermissionPolicies.APPROVE_WRITE) {
    this.policy = policy;
    /** @type {Map<string, { resolve: Function, reject: Function, toolName: string, args: object, level: string }>} */
    this._pendingApprovals = new Map();
  }

  setPolicy(policy) {
    this.policy = policy;
  }

  /**
   * Check if a tool with a given permission level requires explicit user approval.
   *
   * @param {string} permissionLevel One of PermissionLevels
   * @param {string} toolName Name of the tool
   * @param {object} args Arguments passed to the tool
   * @returns {{ requiresApproval: boolean, denied: boolean }}
   */
  checkPermission(permissionLevel = PermissionLevels.READ, toolName = '', args = {}) {
    if (this.policy === PermissionPolicies.NEVER_ALLOW) {
      return { requiresApproval: false, denied: true };
    }

    if (this.policy === PermissionPolicies.AUTO_ALL) {
      // Destructive actions might still request approval unless explicitly bypassed
      if (permissionLevel === PermissionLevels.DESTRUCTIVE) {
        return { requiresApproval: true, denied: false };
      }
      return { requiresApproval: false, denied: false };
    }

    if (this.policy === PermissionPolicies.APPROVE_ALL) {
      return { requiresApproval: true, denied: false };
    }

    // Default policy: APPROVE_WRITE
    // READ is auto-approved. WRITE, EXECUTE, DESTRUCTIVE require user approval.
    if (permissionLevel === PermissionLevels.READ) {
      return { requiresApproval: false, denied: false };
    }

    return { requiresApproval: true, denied: false };
  }

  /**
   * Create a pending approval promise that resolves when the user approves or rejects.
   *
   * @param {string} requestId Unique ID for this approval request
   * @param {string} toolName Tool name
   * @param {object} args Tool arguments
   * @param {string} level Permission level
   * @returns {Promise<{ approved: boolean, reason?: string }>}
   */
  createPendingApproval(requestId, toolName, args, level = PermissionLevels.WRITE) {
    return new Promise((resolve) => {
      this._pendingApprovals.set(requestId, {
        resolve,
        toolName,
        args,
        level,
      });
    });
  }

  /**
   * Resolve a pending approval request.
   *
   * @param {string} requestId Request identifier
   * @param {boolean} approved Whether user allowed the action
   * @param {string} [reason] Optional rejection reason or modified input
   */
  resolvePendingApproval(requestId, approved, reason = '') {
    const pending = this._pendingApprovals.get(requestId);
    if (pending) {
      this._pendingApprovals.delete(requestId);
      pending.resolve({ approved, reason });
      return true;
    }
    return false;
  }

  /**
   * Cancel all pending approval requests (e.g. on agent cancellation).
   * @param {string} [reason='Agent cancelled by user']
   */
  cancelAllPending(reason = 'Agent cancelled by user') {
    for (const [requestId, pending] of this._pendingApprovals) {
      pending.resolve({ approved: false, reason });
    }
    this._pendingApprovals.clear();
  }
}

module.exports = {
  PermissionManager,
  PermissionLevels,
  PermissionPolicies,
};
