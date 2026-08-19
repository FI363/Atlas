'use strict';
// ─────────────────────────────────────────────────────────────────────────────
// context_manager.js
//
// Compacts an OpenAI-format conversation so it fits within a model's context
// window. Drops the oldest middle turns and inserts a synthetic summary
// message when the estimated token count exceeds the budget.
// ─────────────────────────────────────────────────────────────────────────────

const CHARS_PER_TOKEN = 4;   // Heuristic: 1 token ≈ 4 chars (English text)

/**
 * Estimate the number of tokens in a message array.
 * Uses a fast chars/4 heuristic; accurate enough for compaction decisions.
 */
function estimateTokens(messages) {
  let chars = 0;
  for (const msg of messages) {
    chars += JSON.stringify(msg).length;
  }
  return Math.ceil(chars / CHARS_PER_TOKEN);
}

/**
 * Compact a conversation so its estimated token count fits within `maxTokens`.
 *
 * Strategy:
 *   1. Always keep the system message (index 0 if role==='system').
 *   2. Always keep the last `minTailMessages` messages (most recent context).
 *   3. If still too large, drop messages from the MIDDLE (oldest user/assistant turns).
 *   4. Insert a compaction notice so the model knows context was trimmed.
 *
 * @param {Array}  messages        OpenAI-format message array (mutated copy returned).
 * @param {number} maxTokens       Hard token budget (default: 32768).
 * @param {object} opts
 * @param {number} opts.budgetFraction  Compact when exceeding this fraction (default 0.80).
 * @param {number} opts.minTailMessages Messages always kept from the tail (default 8).
 * @returns {Array} Potentially compacted message array.
 */
function compactConversation(messages, maxTokens = 32768, {
  budgetFraction   = 0.80,
  minTailMessages  = 8,
} = {}) {
  const budget = Math.floor(maxTokens * budgetFraction);
  const estimated = estimateTokens(messages);
  if (estimated <= budget) return messages;   // No compaction needed

  // Separate system prompt
  let systemMsg = null;
  let body = messages;
  if (messages.length > 0 && messages[0].role === 'system') {
    systemMsg = messages[0];
    body = messages.slice(1);
  }

  const tail = body.slice(-minTailMessages);
  const middle = body.slice(0, -minTailMessages);

  // Drop messages from the middle until we're back under budget
  let dropped = 0;
  let compacted = [...middle];

  while (compacted.length > 0) {
    const candidate = systemMsg
      ? [systemMsg, ...compacted, ...tail]
      : [...compacted, ...tail];

    if (estimateTokens(candidate) <= budget) break;

    compacted.shift();   // Drop oldest middle message
    dropped++;
  }

  if (dropped === 0) return messages;  // Nothing helped; return as-is

  const notice = {
    role: 'assistant',
    content: `[Context compacted: ${dropped} earlier message${dropped > 1 ? 's were' : ' was'} removed to fit the context window. Recent conversation and tool results are preserved.]`,
  };

  const result = systemMsg
    ? [systemMsg, notice, ...compacted, ...tail]
    : [notice, ...compacted, ...tail];

  console.log(`[ContextManager] Compacted ${dropped} messages (${estimated} → ${estimateTokens(result)} est. tokens)`);
  return result;
}

module.exports = { compactConversation, estimateTokens };
