'use strict';
// ─────────────────────────────────────────────────────────────────────────────
// patch_engine.js
//
// Applies a unified diff string to a file in the workspace without requiring
// an external `patch` binary. Falls back to whole-file replacement on error.
// ─────────────────────────────────────────────────────────────────────────────

const path = require('path');
const fs   = require('fs');

/**
 * Parse a unified diff into a list of hunks.
 *
 * @param {string} diffText  Unified diff text (output of `diff -u` or similar).
 * @returns {Array<{startLine: number, lines: string[]}>}
 */
function parseUnifiedDiff(diffText) {
  const lines = diffText.split('\n');
  const hunks = [];
  let current = null;

  for (const line of lines) {
    const hunkHeader = line.match(/^@@ -(\d+)(?:,\d+)? \+(\d+)(?:,\d+)? @@/);
    if (hunkHeader) {
      if (current) hunks.push(current);
      current = { startLine: parseInt(hunkHeader[2], 10), lines: [] };
      continue;
    }
    if (current) {
      current.lines.push(line);
    }
  }
  if (current) hunks.push(current);
  return hunks;
}

/**
 * Apply a unified diff to `originalText` and return the patched string.
 *
 * @param {string} originalText
 * @param {string} diffText
 * @returns {{ ok: boolean, result: string, error?: string }}
 */
function applyDiffToString(originalText, diffText) {
  const origLines = originalText.split('\n');
  const hunks     = parseUnifiedDiff(diffText);

  if (hunks.length === 0) {
    return { ok: true, result: originalText };
  }

  try {
    const output = [...origLines];
    // Apply hunks in reverse order so earlier hunks don't shift line numbers
    for (const hunk of [...hunks].reverse()) {
      let origIdx  = hunk.startLine - 1;  // 1-based to 0-based
      let newLines = [];

      for (const line of hunk.lines) {
        if (line.startsWith('+')) {
          newLines.push(line.slice(1));
        } else if (line.startsWith('-')) {
          origIdx++;   // Skip original line (it's being removed)
        } else if (line.startsWith(' ') || line === '') {
          newLines.push(line.startsWith(' ') ? line.slice(1) : line);
          origIdx++;
        }
      }

      // Count removed lines
      const removedCount = hunk.lines.filter((l) => l.startsWith('-') || l.startsWith(' ')).length;
      output.splice(hunk.startLine - 1, removedCount, ...newLines);
    }

    return { ok: true, result: output.join('\n') };
  } catch (err) {
    return { ok: false, result: originalText, error: err.message };
  }
}

/**
 * Apply a unified diff to a workspace file.
 *
 * @param {string} workspaceRoot
 * @param {string} filePath       Relative path within workspace.
 * @param {string} diffText       Unified diff string.
 * @returns {{ ok: boolean, path: string, error?: string }}
 */
function applyPatch(workspaceRoot, filePath, diffText) {
  const abs = path.resolve(workspaceRoot, filePath);

  // Security: ensure path is inside workspace
  if (!abs.startsWith(path.resolve(workspaceRoot))) {
    return { ok: false, path: filePath, error: 'Path traversal detected' };
  }

  let original = '';
  try {
    original = fs.readFileSync(abs, 'utf8');
  } catch (e) {
    // New file — diff will add all lines from scratch
  }

  const { ok, result, error } = applyDiffToString(original, diffText);
  if (!ok) {
    return { ok: false, path: filePath, error };
  }

  try {
    fs.mkdirSync(path.dirname(abs), { recursive: true });
    fs.writeFileSync(abs, result, 'utf8');
    return { ok: true, path: filePath };
  } catch (e) {
    return { ok: false, path: filePath, error: e.message };
  }
}

module.exports = { applyPatch, applyDiffToString, parseUnifiedDiff };
