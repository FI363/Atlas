function generateUnifiedDiff(filePath, originalContent = '', newContent = '') {
  const origLines = originalContent ? originalContent.split('\n') : [];
  const newLines = newContent ? newContent.split('\n') : [];

  let diff = `--- a/${filePath}\n+++ b/${filePath}\n`;

  // Simple Myers/LCS diff algorithm for clean patch representation
  const matrix = Array(origLines.length + 1).fill(null).map(() => Array(newLines.length + 1).fill(0));

  for (let i = 0; i < origLines.length; i++) {
    for (let j = 0; j < newLines.length; j++) {
      if (origLines[i] === newLines[j]) {
        matrix[i + 1][j + 1] = matrix[i][j] + 1;
      } else {
        matrix[i + 1][j + 1] = Math.max(matrix[i + 1][j], matrix[i][j + 1]);
      }
    }
  }

  let i = origLines.length;
  let j = newLines.length;
  const edits = [];

  while (i > 0 || j > 0) {
    if (i > 0 && j > 0 && origLines[i - 1] === newLines[j - 1]) {
      edits.unshift({ type: 'keep', line: origLines[i - 1], origLineNum: i, newLineNum: j });
      i--;
      j--;
    } else if (j > 0 && (i === 0 || matrix[i][j - 1] >= matrix[i - 1][j])) {
      edits.unshift({ type: 'add', line: newLines[j - 1], newLineNum: j });
      j--;
    } else if (i > 0 && (j === 0 || matrix[i][j - 1] < matrix[i - 1][j])) {
      edits.unshift({ type: 'remove', line: origLines[i - 1], origLineNum: i });
      i--;
    }
  }

  // Format edits into hunks
  let currentHunk = null;
  const hunks = [];

  for (let idx = 0; idx < edits.length; idx++) {
    const edit = edits[idx];
    if (edit.type === 'keep') {
      // Check if context line should be included
      const hasUpcomingEdit = edits.slice(idx + 1, idx + 4).some(e => e.type !== 'keep');
      const hasRecentEdit = hunks.length > 0 && currentHunk;

      if (hasUpcomingEdit || hasRecentEdit) {
        if (!currentHunk) {
          currentHunk = { lines: [] };
          hunks.push(currentHunk);
        }
        currentHunk.lines.push(` ${edit.line}`);
      } else {
        currentHunk = null;
      }
    } else {
      if (!currentHunk) {
        currentHunk = { lines: [] };
        hunks.push(currentHunk);
      }
      if (edit.type === 'add') {
        currentHunk.lines.push(`+${edit.line}`);
      } else if (edit.type === 'remove') {
        currentHunk.lines.push(`-${edit.line}`);
      }
    }
  }

  if (hunks.length === 0) {
    return { diff: '', hasChanges: false, hunks: [] };
  }

  for (const hunk of hunks) {
    diff += `@@ -1,${origLines.length} +1,${newLines.length} @@\n`;
    diff += hunk.lines.join('\n') + '\n';
  }

  return {
    filePath,
    diff,
    hasChanges: true,
    hunks,
    originalContent,
    newContent,
  };
}

module.exports = {
  generateUnifiedDiff,
};
