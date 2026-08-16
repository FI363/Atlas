const crypto = require('crypto');

const PERMISSION_CATEGORIES = {
  READ: 'READ',
  WRITE: 'WRITE',
  EXECUTE: 'EXECUTE',
};

const TOOL_PERMISSIONS = {
  // Filesystem
  list_directory: PERMISSION_CATEGORIES.READ,
  read_file: PERMISSION_CATEGORIES.READ,
  write_file: PERMISSION_CATEGORIES.WRITE,
  create_file: PERMISSION_CATEGORIES.WRITE,
  delete_file: PERMISSION_CATEGORIES.WRITE,
  move_file: PERMISSION_CATEGORIES.WRITE,

  // Search
  search_code: PERMISSION_CATEGORIES.READ,
  find_files: PERMISSION_CATEGORIES.READ,

  // Git
  git_status: PERMISSION_CATEGORIES.READ,
  git_diff: PERMISSION_CATEGORIES.READ,
  git_log: PERMISSION_CATEGORIES.READ,

  // Execution
  run_command: PERMISSION_CATEGORIES.EXECUTE,
  run_tests: PERMISSION_CATEGORIES.EXECUTE,
  run_build: PERMISSION_CATEGORIES.EXECUTE,

  // Context & LSP
  get_project_info: PERMISSION_CATEGORIES.READ,
  get_workspace_structure: PERMISSION_CATEGORIES.READ,
  get_diagnostics: PERMISSION_CATEGORIES.READ,
  get_symbols: PERMISSION_CATEGORIES.READ,
};

class PermissionManager {
  constructor(policy = 'approve_write') {
    // Policies: 'approve_write' (READ auto, WRITE/EXECUTE prompt), 'approve_all', 'auto_all'
    this.policy = policy;
    this.pendingApprovals = new Map();
  }

  setPolicy(policy) {
    if (['approve_write', 'approve_all', 'auto_all'].includes(policy)) {
      this.policy = policy;
    }
  }

  getToolCategory(toolName) {
    return TOOL_PERMISSIONS[toolName] || PERMISSION_CATEGORIES.EXECUTE;
  }

  checkPermission(toolName, args = {}) {
    const category = this.getToolCategory(toolName);

    if (this.policy === 'auto_all') {
      return { allowed: true, requiresApproval: false, category };
    }

    if (this.policy === 'approve_all') {
      const requestId = crypto.randomUUID();
      return { allowed: false, requiresApproval: true, category, requestId };
    }

    // Default 'approve_write' policy: READ is auto, WRITE & EXECUTE require approval
    if (category === PERMISSION_CATEGORIES.READ) {
      return { allowed: true, requiresApproval: false, category };
    } else {
      const requestId = crypto.randomUUID();
      return { allowed: false, requiresApproval: true, category, requestId };
    }
  }

  createPendingApproval(requestId, toolName, args, category) {
    return new Promise((resolve) => {
      this.pendingApprovals.set(requestId, {
        requestId,
        toolName,
        args,
        category,
        resolve,
        timestamp: Date.now(),
      });
    });
  }

  grantPending(requestId) {
    const pending = this.pendingApprovals.get(requestId);
    if (pending) {
      this.pendingApprovals.delete(requestId);
      pending.resolve({ allowed: true });
      return true;
    }
    return false;
  }

  denyPending(requestId, reason = 'User denied permission request') {
    const pending = this.pendingApprovals.get(requestId);
    if (pending) {
      this.pendingApprovals.delete(requestId);
      pending.resolve({ allowed: false, reason });
      return true;
    }
    return false;
  }

  cancelAllPending(reason = 'Agent session cancelled') {
    for (const [requestId, pending] of this.pendingApprovals.entries()) {
      pending.resolve({ allowed: false, reason });
    }
    this.pendingApprovals.clear();
  }
}

module.exports = {
  PERMISSION_CATEGORIES,
  TOOL_PERMISSIONS,
  PermissionManager,
};
