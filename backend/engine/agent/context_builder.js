'use strict';
// ─────────────────────────────────────────────────────────────────────────────
// context_builder.js
//
// Builds the agent system prompt, optionally injecting snippets from relevant
// workspace files (automatic context selection).
// ─────────────────────────────────────────────────────────────────────────────

const path = require('path');
const fs   = require('fs');

/**
 * Select files relevant to the current prompt.
 *
 * Uses ripgrep (via child_process) when available, falling back to a plain
 * string search over the FileIndex. Returns up to `maxFiles` entries with
 * a short snippet for system-prompt injection.
 *
 * @param {object} ideContext
 * @param {string} workspaceRoot
 * @param {string} prompt
 * @param {number} maxFiles
 * @returns {Array<{path: string, snippet: string}>}
 */
function selectRelevantFiles(ideContext, workspaceRoot, prompt, maxFiles = 8) {
  try {
    const { fileIndex } = require('../indexer/file_index');

    // Extract candidate search terms from the prompt (words ≥ 4 chars, capitalised, or camelCase)
    const terms = extractSearchTerms(prompt);
    if (terms.length === 0) return [];

    const scored = new Map();   // path → score

    // Score by file name / path match
    for (const term of terms) {
      const byName = fileIndex.findByName(term);
      for (const entry of byName) {
        scored.set(entry.path, (scored.get(entry.path) || 0) + 2);
      }
    }

    // Boost files near the active file
    const activeFile = ideContext.activeFile;
    if (activeFile) {
      const activeDir = path.dirname(activeFile);
      for (const [p, score] of scored) {
        if (path.dirname(p) === activeDir) {
          scored.set(p, score + 1);
        }
      }
    }

    // Boost recently modified files
    const recent = fileIndex.getRecentlyModified(20);
    for (const entry of recent) {
      if (scored.has(entry.path)) {
        scored.set(entry.path, (scored.get(entry.path) || 0) + 1);
      }
    }

    const ranked = Array.from(scored.entries())
      .sort((a, b) => b[1] - a[1])
      .slice(0, maxFiles)
      .map(([p]) => p);

    // Read short snippets (first 30 lines)
    const results = [];
    for (const relPath of ranked) {
      try {
        const abs     = path.join(workspaceRoot, relPath);
        const content = fs.readFileSync(abs, 'utf8');
        const snippet = content.split('\n').slice(0, 30).join('\n');
        results.push({ path: relPath, snippet });
      } catch { /* skip unreadable files */ }
    }
    return results;
  } catch {
    return [];
  }
}

/**
 * Extract useful search terms from a prompt string.
 */
function extractSearchTerms(prompt) {
  const words = prompt.match(/\b[A-Za-z][a-zA-Z0-9_]{3,}\b/g) || [];
  // Deduplicate and filter stop words
  const stopWords = new Set(['this', 'that', 'with', 'from', 'have', 'will', 'just', 'file', 'code', 'make', 'need', 'want', 'should', 'would', 'could', 'there', 'then', 'when', 'your', 'also', 'like', 'what', 'some', 'into', 'over', 'after', 'before', 'function', 'class', 'method', 'variable', 'return', 'import']);
  const seen = new Set();
  const terms = [];
  for (const w of words) {
    const lower = w.toLowerCase();
    if (!stopWords.has(lower) && !seen.has(lower)) {
      seen.add(lower);
      terms.push(w);
    }
  }
  return terms.slice(0, 10);
}

/**
 * Build the full system prompt for an agent run.
 *
 * @param {object} ideContext   Context from the Flutter IDE.
 * @param {object} settings     AtlasSettings payload from the client.
 * @returns {string}
 */
function buildAgentSystemPrompt(ideContext = {}, settings = {}) {
  const customSystemPrompt = settings.aiSystemPrompt || '';
  const workspaceRoot = ideContext.cwd || ideContext.workspaceRoot || '';
  const projectName   = ideContext.projectName || 'atlas';
  const activeFile    = ideContext.activeFile  || null;
  const cursor        = ideContext.cursor       || null;
  const selection     = ideContext.selection    || null;
  const openFiles     = Array.isArray(ideContext.openFiles) ? ideContext.openFiles : [];

  let prompt = `You are Atlas Agent, an intelligent agentic AI software engineer built directly into the Atlas IDE on iPad.

ENVIRONMENT CONTEXT:
- Project Name: ${projectName}
- Workspace Root: ${workspaceRoot}
`;

  if (activeFile) prompt += `- Active File in Editor: ${activeFile}\n`;
  if (cursor)     prompt += `- Editor Cursor Position: Line ${cursor.line || 1}, Column ${cursor.column || 1}\n`;
  if (selection)  prompt += `- Selected Text:\n\`\`\`\n${selection}\n\`\`\`\n`;
  if (openFiles.length > 0) {
    prompt += `- Currently Open Tabs in Editor:\n`;
    for (const f of openFiles) {
      prompt += `  * ${typeof f === 'string' ? f : f.path}\n`;
    }
  }

  // Auto context selection: inject snippets from relevant files
  if (workspaceRoot && ideContext.prompt) {
    const relevant = selectRelevantFiles(ideContext, workspaceRoot, ideContext.prompt);
    if (relevant.length > 0) {
      prompt += `\nRELEVANT WORKSPACE FILES (auto-selected):\n`;
      for (const { path: p, snippet } of relevant) {
        prompt += `\n### ${p}\n\`\`\`\n${snippet}\n\`\`\`\n`;
      }
    }
  }

  prompt += `
OPERATIONAL DIRECTIVES:
1. Work iteratively using the provided tools to inspect, search, read, modify, and verify code.
2. ALWAYS verify your hypothesis before making code edits. Use search_code, read_file, or get_diagnostics to investigate.
3. When modifying files, prefer apply_patch with a unified diff over write_file to minimise diffs. Diffs are presented to the user for approval.
4. After editing code, run tests (run_tests) or diagnostics (get_diagnostics) to confirm your fix worked.
5. If run_tests shows failures, inspect the error output, fix the code, and run tests again. Keep iterating until tests pass.
6. Be concise and direct in your progress explanations. Explain WHAT you are inspecting and WHY.
7. Maximise accuracy — do not guess file paths or function definitions without reading them first.
8. When the user cancels, stop immediately without further tool calls.
`;

  if (customSystemPrompt) {
    prompt += `\nADDITIONAL USER INSTRUCTIONS:\n${customSystemPrompt}\n`;
  }

  return prompt;
}

module.exports = { buildAgentSystemPrompt, selectRelevantFiles, extractSearchTerms };
