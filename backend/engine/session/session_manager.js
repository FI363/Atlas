const crypto = require('crypto');

class AgentSession {
  constructor({
    sessionId = crypto.randomUUID(),
    workspaceRoot = process.cwd(),
    providerId = 'gemini',
    modelId = 'gemini-2.5-flash',
  } = {}) {
    this.sessionId = sessionId;
    this.workspaceRoot = workspaceRoot;
    this.providerId = providerId;
    this.modelId = modelId;
    this.task = '';
    this.conversation = [];
    this.toolHistory = [];
    this.status = 'idle'; // 'idle' | 'running' | 'completed' | 'cancelled' | 'error'
    this.createdAt = Date.now();
    this.updatedAt = Date.now();
    this._isRunning = false;
  }

  /**
   * Switch the model/provider used for subsequent turns in this session.
   * Preserves full conversation history and tool outputs.
   *
   * @param {string} providerId
   * @param {string} modelId
   */
  switchModel(providerId, modelId) {
    this.providerId = providerId;
    this.modelId = modelId;
    this.updatedAt = Date.now();
  }

  startRun(task) {
    if (this._isRunning) return false;
    this._isRunning = true;
    this.status = 'running';
    if (task) this.task = task;
    this.updatedAt = Date.now();
    return true;
  }

  finishRun(status = 'completed') {
    this._isRunning = false;
    this.status = status;
    this.updatedAt = Date.now();
  }

  addMessage(message) {
    this.conversation.push(message);
    this.updatedAt = Date.now();
  }

  recordToolExecution(toolCall, result) {
    this.toolHistory.push({
      toolName: toolCall.name,
      args: toolCall.args,
      result,
      timestamp: Date.now(),
    });
    this.updatedAt = Date.now();
  }
}

class SessionManager {
  constructor() {
    /** @type {Map<string, AgentSession>} */
    this._sessions = new Map();
  }

  /**
   * Get an existing session or create a new one.
   *
   * @param {string} [sessionId]
   * @param {object} [initProps]
   * @returns {AgentSession}
   */
  getOrCreate(sessionId, initProps = {}) {
    if (sessionId && this._sessions.has(sessionId)) {
      const session = this._sessions.get(sessionId);
      if (initProps.workspaceRoot) session.workspaceRoot = initProps.workspaceRoot;
      return session;
    }

    const id = sessionId || crypto.randomUUID();
    const session = new AgentSession({ sessionId: id, ...initProps });
    this._sessions.set(id, session);
    return session;
  }

  /**
   * Get a session by ID.
   * @param {string} sessionId
   * @returns {AgentSession|null}
   */
  getSession(sessionId) {
    return this._sessions.get(sessionId) || null;
  }

  /**
   * Remove a session.
   * @param {string} sessionId
   */
  deleteSession(sessionId) {
    this._sessions.delete(sessionId);
  }

  /**
   * List all active sessions.
   */
  listSessions() {
    return Array.from(this._sessions.values()).map((s) => ({
      sessionId: s.sessionId,
      task: s.task,
      providerId: s.providerId,
      modelId: s.modelId,
      status: s.status,
      messageCount: s.conversation.length,
      createdAt: s.createdAt,
      updatedAt: s.updatedAt,
    }));
  }
}

module.exports = {
  AgentSession,
  SessionManager,
};
