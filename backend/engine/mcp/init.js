const { globalRegistry } = require('./registry');
const { registerFilesystemTools } = require('./tools/filesystem_tools');
const { registerSearchTools } = require('./tools/search_tools');
const { registerGitTools } = require('./tools/git_tools');
const { registerExecutionTools } = require('./tools/execution_tools');
const { registerContextTools } = require('./tools/context_tools');

function initializeMcpTools() {
  registerFilesystemTools(globalRegistry);
  registerSearchTools(globalRegistry);
  registerGitTools(globalRegistry);
  registerExecutionTools(globalRegistry);
  registerContextTools(globalRegistry);
  return globalRegistry;
}

module.exports = {
  initializeMcpTools,
  globalRegistry,
};
