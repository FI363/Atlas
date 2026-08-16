const MAX_SESSIONS = 100;
const MAX_IDLE_MS = 12 * 60 * 60 * 1000;

/**
 * Owns the transcript for one Atlas chat session. AgentLoop instances are
 * deliberately short-lived runs, while this object survives between turns
 * (and between WebSocket reconnects) for the same client session id.
 */
class ConversationSession {
  constructor(id, workspaceRoot) {
    this.id = id;
    this.workspaceRoot = workspaceRoot;
    this.conversation = [];
    this.isRunning = false;
    this.lastActivityAt = Date.now();
  }

  touch(workspaceRoot) {
    if (workspaceRoot) this.workspaceRoot = workspaceRoot;
    this.lastActivityAt = Date.now();
  }

  startRun() {
    if (this.isRunning) return false;
    this.isRunning = true;
    this.touch();
    return true;
  }

  finishRun() {
    this.isRunning = false;
    this.touch();
  }
}

class ConversationSessionStore {
  constructor({ maxSessions = MAX_SESSIONS, maxIdleMs = MAX_IDLE_MS } = {}) {
    this.maxSessions = maxSessions;
    this.maxIdleMs = maxIdleMs;
    this.sessions = new Map();
  }

  getOrCreate(id, workspaceRoot) {
    this.prune();
    let session = this.sessions.get(id);
    if (!session) {
      if (this.sessions.size >= this.maxSessions) this.evictOldestIdleSession();
      session = new ConversationSession(id, workspaceRoot);
      this.sessions.set(id, session);
    } else {
      session.touch(workspaceRoot);
    }
    return session;
  }

  prune() {
    const cutoff = Date.now() - this.maxIdleMs;
    for (const [id, session] of this.sessions) {
      if (!session.isRunning && session.lastActivityAt < cutoff) this.sessions.delete(id);
    }
  }

  evictOldestIdleSession() {
    const idleSessions = [...this.sessions.values()]
      .filter((session) => !session.isRunning)
      .sort((a, b) => a.lastActivityAt - b.lastActivityAt);
    if (idleSessions[0]) this.sessions.delete(idleSessions[0].id);
  }
}

function isValidConversationSessionId(value) {
  return typeof value === 'string' && /^[A-Za-z0-9_-]{8,128}$/.test(value);
}

module.exports = {
  ConversationSession,
  ConversationSessionStore,
  isValidConversationSessionId,
};
