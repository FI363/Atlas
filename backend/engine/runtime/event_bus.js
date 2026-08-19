const EventEmitter = require('events');

/**
 * Standard typed event names emitted by the Agent Runtime.
 */
const AgentEvents = {
  STARTED: 'agent.started',
  MESSAGE: 'agent.message',
  TOKEN: 'agent.token',
  TOOL_CALL: 'agent.tool_call',
  TOOL_RESULT: 'agent.tool_result',
  FILE_CHANGED: 'agent.file_changed',
  COMMAND_STARTED: 'agent.command_started',
  COMMAND_OUTPUT: 'agent.command_output',
  COMMAND_FINISHED: 'agent.command_finished',
  PERMISSION_REQUESTED: 'agent.permission_requested',
  PERMISSION_RESOLVED: 'agent.permission_resolved',
  DIFF_PROPOSED: 'agent.diff_proposed',
  DIFF_RESOLVED: 'agent.diff_resolved',
  MODEL_CHANGED: 'agent.model_changed',
  COMPLETED: 'agent.completed',
  FAILED: 'agent.failed',
  CANCELLED: 'agent.cancelled',
};

class EventBus extends EventEmitter {
  constructor() {
    super();
    this.setMaxListeners(50);
  }

  /**
   * Emit a standardized agent runtime event.
   * @param {string} eventName From AgentEvents
   * @param {object} payload Event payload
   */
  emitEvent(eventName, payload = {}) {
    const timestamp = Date.now();
    this.emit(eventName, { event: eventName, timestamp, ...payload });
    this.emit('*', { event: eventName, timestamp, ...payload });
  }
}

module.exports = {
  EventBus,
  AgentEvents,
};
