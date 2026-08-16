const fs = require('fs');
const path = require('path');

function searchWorkspaceFiles(workspaceRoot, dirPath, query, results = [], maxResults = 50) {
  if (!query || query.trim().length === 0) return results;
  const lowerQuery = query.toLowerCase();

  try {
    const items = fs.readdirSync(dirPath, { withFileTypes: true });
    for (const item of items) {
      if (results.length >= maxResults) break;
      if (item.name.startsWith('.') || item.name === 'build' || item.name === 'node_modules') continue;

      const fullPath = path.join(dirPath, item.name);
      if (item.isDirectory()) {
        searchWorkspaceFiles(workspaceRoot, fullPath, query, results, maxResults);
      } else if (item.isFile()) {
        const ext = path.extname(item.name).toLowerCase();
        if (['.png', '.jpg', '.jpeg', '.gif', '.ico', '.pdf', '.zip', '.exe', '.dll'].includes(ext)) continue;

        try {
          const content = fs.readFileSync(fullPath, 'utf-8');
          const lines = content.split('\n');
          const relPath = path.relative(workspaceRoot, fullPath).replace(/\\/g, '/');

          for (let i = 0; i < lines.length; i++) {
            if (results.length >= maxResults) break;
            if (lines[i].toLowerCase().includes(lowerQuery)) {
              results.push({
                path: relPath,
                line: i + 1,
                snippet: lines[i].trim(),
              });
            }
          }
        } catch { }
      }
    }
  } catch (e) {
    console.error(`Search error in ${dirPath}: ${e.message}`);
  }
  return results;
}

function findFiles(workspaceRoot, dirPath = workspaceRoot, pattern = '', results = [], maxResults = 100) {
  const lowerPattern = pattern.toLowerCase();

  try {
    const items = fs.readdirSync(dirPath, { withFileTypes: true });
    for (const item of items) {
      if (results.length >= maxResults) break;
      if (item.name.startsWith('.') || item.name === 'build' || item.name === 'node_modules') continue;

      const fullPath = path.join(dirPath, item.name);
      const relPath = path.relative(workspaceRoot, fullPath).replace(/\\/g, '/');

      if (!pattern || item.name.toLowerCase().includes(lowerPattern) || relPath.toLowerCase().includes(lowerPattern)) {
        results.push({
          path: relPath,
          isDirectory: item.isDirectory(),
          name: item.name,
        });
      }

      if (item.isDirectory()) {
        findFiles(workspaceRoot, fullPath, pattern, results, maxResults);
      }
    }
  } catch (e) {
    console.error(`Find error in ${dirPath}: ${e.message}`);
  }
  return results;
}

module.exports = {
  searchWorkspaceFiles,
  findFiles,
};
