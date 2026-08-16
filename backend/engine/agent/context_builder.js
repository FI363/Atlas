function buildAgentSystemPrompt(ideContext = {}, settings = {}) {
  const customSystemPrompt = settings.aiSystemPrompt || '';
  const workspaceRoot = ideContext.cwd || ideContext.workspaceRoot || '';
  const projectName = ideContext.projectName || 'atlas';
  const activeFile = ideContext.activeFile || null;
  const cursor = ideContext.cursor || null;
  const selection = ideContext.selection || null;
  const openFiles = Array.isArray(ideContext.openFiles) ? ideContext.openFiles : [];

  let prompt = `You are Atlas Agent, an intelligent agentic AI software engineer built directly into the Atlas IDE on iPad.

ENVIRONMENT CONTEXT:
- Project Name: ${projectName}
- Workspace Root: ${workspaceRoot}
`;

  if (activeFile) {
    prompt += `- Active File in Editor: ${activeFile}\n`;
  }
  if (cursor) {
    prompt += `- Editor Cursor Position: Line ${cursor.line || 1}, Column ${cursor.column || 1}\n`;
  }
  if (selection) {
    prompt += `- Selected Text:\n\`\`\`\n${selection}\n\`\`\`\n`;
  }
  if (openFiles.length > 0) {
    prompt += `- Currently Open Tabs in Editor:\n`;
    for (const f of openFiles) {
      const p = typeof f === 'string' ? f : f.path;
      prompt += `  * ${p}\n`;
    }
  }

  prompt += `
OPERATIONAL DIRECTIVES:
1. Work iteratively using the provided tools to inspect, search, read, modify, and verify code.
2. ALWAYS verify your hypothesis before making code edits. Use search_code, read_file, or get_diagnostics to investigate.
3. When modifying files using write_file or creating files, provide clean, exact code. Diffs will be presented to the user for approval.
4. After editing code, run tests (run_tests) or build/diagnostics (run_build or get_diagnostics) to confirm your fix worked.
5. Be concise and direct in your progress explanations. Explain WHAT you are inspecting and WHY.
6. Maximize accuracy and do not guess file paths or function definitions without reading them first.
`;

  if (customSystemPrompt) {
    prompt += `\nADDITIONAL USER INSTRUCTIONS:\n${customSystemPrompt}\n`;
  }

  return prompt;
}

module.exports = { buildAgentSystemPrompt };
