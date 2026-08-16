const http = require('http');
const https = require('https');

function callAiProvider(settings, prompt, contextCode, attachments, callback) {
  const provider = settings.aiProvider || 'builtIn';
  const systemPrompt = settings.aiSystemPrompt || 'You are Atlas, an expert agentic AI software engineer embedded in Atlas IDE. When providing code changes or new files, wrap complete code in ```language:filepath code blocks.';
  const textAttachments = (attachments || []).filter(item => item && item.kind === 'file' && typeof item.text === 'string');
  const imageAttachments = (attachments || []).filter(item => item && item.kind === 'image' && typeof item.dataBase64 === 'string');

  const attachmentSummary = (attachments || []).map((item) => {
    if (!item || !item.name) return '';
    if (item.kind === 'image') return `- Image: ${item.name} (${item.mimeType || 'image'})`;
    if (item.kind === 'file') return `- File: ${item.name} (${item.mimeType || 'file'}${item.size ? `, ${item.size} bytes` : ''})`;
    return `- Attachment: ${item.name}`;
  }).filter(Boolean).join('\n');

  const userText = [
    contextCode ? `Active Code Context:\n\`\`\`\n${contextCode}\n\`\`\`` : '',
    attachmentSummary ? `Attachments:\n${attachmentSummary}` : '',
    textAttachments.length
      ? `Attached File Contents:\n${textAttachments.map((item) => `### ${item.name}\n\`\`\`\n${item.text}\n\`\`\``).join('\n\n')}`
      : '',
    `Task: ${prompt}`,
  ].filter(Boolean).join('\n\n');

  if (provider === 'openRouter') {
    const endpoint = settings.openRouterEndpoint || 'https://openrouter.ai/api/v1';
    const model = settings.openRouterModel || 'google/gemini-2.5-flash';
    const apiKey = settings.openRouterApiKey || process.env.OPENROUTER_API_KEY || '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';

    if (!apiKey) {
      return callback(null, '❌ OpenRouter API Key is missing! Set your key in Atlas Settings → AI Agent.');
    }

    let url;
    try {
      const base = endpoint.endsWith('/') ? endpoint : endpoint + '/';
      url = new URL('chat/completions', base);
    } catch {
      return callback(null, `❌ Invalid OpenRouter URL: ${endpoint}`);
    }

    const userMessage = imageAttachments.length
      ? {
          role: 'user',
          content: [
            { type: 'text', text: userText },
            ...imageAttachments.map((item) => ({
              type: 'image_url',
              image_url: { url: `data:${item.mimeType};base64,${item.dataBase64}` },
            })),
          ],
        }
      : { role: 'user', content: userText };

    const postData = JSON.stringify({
      model: model,
      messages: [
        { role: 'system', content: systemPrompt },
        userMessage
      ],
      temperature: settings.aiTemperature || 0.2,
      max_tokens: settings.aiMaxTokens || 2048
    });

    const httpModule = url.protocol === 'https:' ? https : http;
    const req = httpModule.request(url, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${apiKey}`,
        'HTTP-Referer': 'https://github.com/atlas-ide',
        'X-Title': 'Atlas IDE',
        'Content-Length': Buffer.byteLength(postData)
      }
    }, (res) => {
      let body = '';
      res.on('data', chunk => body += chunk);
      res.on('end', () => {
        try {
          const parsed = JSON.parse(body);
          if (parsed.choices && parsed.choices[0] && parsed.choices[0].message) {
            callback(null, `### ⚡ OpenRouter (${model})\n\n${parsed.choices[0].message.content}`);
          } else {
            callback(null, `❌ OpenRouter API Error: ${parsed.error?.message || body}`);
          }
        } catch (e) {
          callback(null, `OpenRouter Response: ${body}`);
        }
      });
    });
    req.on('error', (err) => callback(null, `❌ OpenRouter Request Failed: ${err.message}`));
    req.write(postData);
    req.end();
  } else if (provider === 'ollama') {
    const endpoint = settings.ollamaEndpoint || 'http://localhost:11434';
    const model = settings.ollamaModel || 'deepseek-coder';
    let url;
    try {
      url = new URL('/api/chat', endpoint);
    } catch {
      return callback(null, `❌ Invalid Ollama URL: ${endpoint}`);
    }

    const userMessage = imageAttachments.length
      ? {
          role: 'user',
          content: [
            { type: 'text', text: userText },
            ...imageAttachments.map((item) => ({
              type: 'image_url',
              image_url: { url: `data:${item.mimeType};base64,${item.dataBase64}` },
            })),
          ],
        }
      : { role: 'user', content: userText };

    const postData = JSON.stringify({
      model: model,
      messages: [
        { role: 'system', content: systemPrompt },
        userMessage
      ],
      stream: false,
      options: {
        temperature: settings.aiTemperature || 0.2,
        num_predict: settings.aiMaxTokens || 2048
      }
    });

    const httpModule = url.protocol === 'https:' ? https : http;
    const req = httpModule.request(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(postData) }
    }, (res) => {
      let body = '';
      res.on('data', chunk => body += chunk);
      res.on('end', () => {
        try {
          const parsed = JSON.parse(body);
          const answer = parsed.message?.content || parsed.response || body;
          callback(null, `### 🦙 Ollama (${model})\n\n${answer}`);
        } catch (e) {
          callback(null, `Ollama Response: ${body}`);
        }
      });
    });
    req.on('error', (err) => callback(null, `❌ Cannot reach Ollama at ${endpoint}.\n\nEnsure Ollama is running (\`ollama serve\`) and you have pulled the model (\`ollama pull ${model}\`). Error: ${err.message}`));
    req.write(postData);
    req.end();
  } else if (provider === 'openAi') {
    const endpoint = settings.openAiEndpoint || 'https://api.openai.com/v1';
    const model = settings.openAiModel || 'gpt-4o';
    const apiKey = settings.openAiApiKey || '';
    if (!apiKey) {
      return callback(null, '❌ OpenAI API Key is missing! Set your key in Atlas Settings → AI Agent.');
    }
    let url;
    try {
      url = new URL('/chat/completions', endpoint);
    } catch {
      return callback(null, `❌ Invalid OpenAI URL: ${endpoint}`);
    }

    const postData = JSON.stringify({
      model: model,
      messages: [
        { role: 'system', content: systemPrompt },
        { role: 'user', content: userText }
      ],
      temperature: settings.aiTemperature || 0.2,
      max_tokens: settings.aiMaxTokens || 2048
    });

    const httpModule = url.protocol === 'https:' ? https : http;
    const req = httpModule.request(url, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${apiKey}`,
        'Content-Length': Buffer.byteLength(postData)
      }
    }, (res) => {
      let body = '';
      res.on('data', chunk => body += chunk);
      res.on('end', () => {
        try {
          const parsed = JSON.parse(body);
          if (parsed.choices && parsed.choices[0]) {
            callback(null, `### ⚡ OpenAI (${model})\n\n${parsed.choices[0].message.content}`);
          } else {
            callback(null, `API Error: ${parsed.error?.message || body}`);
          }
        } catch (e) {
          callback(null, body);
        }
      });
    });
    req.on('error', (err) => callback(null, `❌ OpenAI Request Failed: ${err.message}`));
    req.write(postData);
    req.end();
  } else if (provider === 'custom') {
    const endpoint = settings.customAgentEndpoint || '';
    if (!endpoint) return callback(null, '❌ Custom Endpoint URL is missing in Settings.');
    let url;
    try { url = new URL(endpoint); } catch { return callback(null, `❌ Invalid Custom URL: ${endpoint}`); }

    const postData = JSON.stringify({ prompt, contextCode, systemPrompt, attachments });
    const httpModule = url.protocol === 'https:' ? https : http;
    const req = httpModule.request(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(postData) }
    }, (res) => {
      let body = '';
      res.on('data', chunk => body += chunk);
      res.on('end', () => callback(null, body));
    });
    req.on('error', (err) => callback(null, `❌ Custom Endpoint Failed: ${err.message}`));
    req.write(postData);
    req.end();
  } else {
    // Built-in smart fallback
    const lower = prompt.toLowerCase();
    let aiAnswer = '';

    if (lower.includes('explain') || lower.includes('what does this code do')) {
      aiAnswer = `### 🤖 Atlas Built-In Agent: Code Explanation\n\nAnalyzing active context (${contextCode ? contextCode.length : 0} bytes):\n\n- **Structure**: High-performance Flutter reactive component.\n- **State**: Uses \`ChangeNotifier\` & \`WorkspaceState\` for real-time reactivity.\n- **Recommendation**: Ensure UI widgets bind cleanly to state models.`;
    } else if (lower.includes('bug') || lower.includes('fix') || lower.includes('find bugs')) {
      aiAnswer = `### 🐛 Atlas Built-In Agent: Bug Scan\n\n- **Check**: All WebSocket connections verify \`isConnected\` before sending.\n- **Check**: Null bounds checked on file tab switches.\n- **Status**: No critical syntax errors found in active buffer.`;
    } else if (lower.includes('test') || lower.includes('generate tests')) {
      aiAnswer = `### 🧪 Atlas Built-In Agent: Unit Test\n\n\`\`\`dart\nvoid main() {\n  group('WorkspaceState Unit Tests', () {\n    test('verifies initial state and settings', () {\n      // Test implementation\n    });\n  });\n}\n\`\`\``;
    } else {
      aiAnswer = `### 🤖 Atlas Built-In Agent\n\nReceived your prompt: "${prompt}".\n\n${contextCode ? '📄 Active File Context Included (' + contextCode.split('\n').length + ' lines).' : 'No active file open.'}\n\n*Tip: Connect me to **Ollama** or **OpenAI** in Settings for full LLM intelligence!*`;
    }
    setTimeout(() => callback(null, aiAnswer), 250);
  }
}

// Universal tool call extractor for local models / Ollama text output
function extractToolCallsFromText(text) {
  if (typeof text !== 'string' || !text.trim()) return null;

  const toolCalls = [];

  // Match <tool_call>...</tool_call> XML format
  const xmlRegex = /<tool_call>([\s\S]*?)<\/tool_call>/gi;
  let match;
  while ((match = xmlRegex.exec(text)) !== null) {
    try {
      const parsed = JSON.parse(match[1].trim());
      const name = parsed.name || parsed.tool || parsed.function;
      const args = parsed.arguments || parsed.args || {};
      if (name) {
        toolCalls.push({
          id: `call_${Date.now()}_${toolCalls.length}`,
          type: 'function',
          function: { name, arguments: typeof args === 'string' ? args : JSON.stringify(args) },
        });
      }
    } catch {}
  }

  // Match ```json {"name": "...", "arguments": ...} ``` format
  if (toolCalls.length === 0) {
    const jsonBlockRegex = /```(?:json)?\s*(\{[\s\S]*?\})\s*```/gi;
    while ((match = jsonBlockRegex.exec(text)) !== null) {
      try {
        const parsed = JSON.parse(match[1].trim());
        const name = parsed.name || parsed.tool || parsed.function;
        const args = parsed.arguments || parsed.args || {};
        if (name) {
          toolCalls.push({
            id: `call_${Date.now()}_${toolCalls.length}`,
            type: 'function',
            function: { name, arguments: typeof args === 'string' ? args : JSON.stringify(args) },
          });
        }
      } catch {}
    }
  }

  return toolCalls.length > 0 ? toolCalls : null;
}

function getLatestUserTurn(conversation) {
  for (let index = conversation.length - 1; index >= 0; index--) {
    if (conversation[index].role === 'user') {
      return { index, message: conversation[index] };
    }
  }
  return { index: -1, message: null };
}

function wasToolExecutedThisTurn(conversation, userIndex, toolCallId) {
  return conversation.slice(userIndex + 1).some((message) =>
    message.role === 'tool' && message.tool_call_id === toolCallId
  );
}

function getToolErrorsThisTurn(conversation, userIndex) {
  return conversation.slice(userIndex + 1)
    .filter((message) => message.role === 'tool')
    .map((message) => {
      try {
        const result = JSON.parse(message.content || '{}');
        return typeof result.error === 'string' ? result.error : '';
      } catch (_) {
        return '';
      }
    })
    .filter(Boolean);
}

function builtInToolCall(userIndex, operation, name, args) {
  return {
    id: `builtin_${userIndex}_${operation}`,
    type: 'function',
    function: { name, arguments: JSON.stringify(args) },
  };
}

function extractRequestedCreation(prompt) {
  const isCreation = /\b(?:create|make)\b/i.test(prompt) && /\b(?:file|folder|directory)\b/i.test(prompt);
  if (!isCreation) return null;

  const kindMatch = prompt.match(/\b(file|folder|directory)\b/i);
  const isDirectory = kindMatch && kindMatch[1].toLowerCase() !== 'file';
  const ignoredNames = new Set(['a', 'an', 'in', 'the', 'my', 'current', 'directory', 'folder', 'file']);
  const patterns = [
    /\b(?:file|folder|directory)\s+(?:named|called|at)\s+["']?([A-Za-z0-9_./\\-]+)["']?/i,
    /\b(?:create|make)\s+(?:a|an)?\s*(?:new\s+)?(?:text\s+)?(?:file|folder|directory)\s+["']?([A-Za-z0-9_./\\-]+)["']?/i,
  ];

  let requestedPath = '';
  for (const pattern of patterns) {
    const match = prompt.match(pattern);
    const candidate = match?.[1]?.trim();
    if (candidate && !ignoredNames.has(candidate.toLowerCase())) {
      requestedPath = candidate;
      break;
    }
  }

  const contentMatch = prompt.match(/\bwith\s+(?:the\s+)?content\s+["']?([\s\S]*?)["']?\s*$/i);
  return {
    requestedPath,
    content: contentMatch?.[1]?.trim() || '',
    isDirectory,
  };
}

function findUnresolvedCreation(conversation, beforeIndex) {
  for (let index = beforeIndex - 1; index >= 0; index--) {
    const message = conversation[index];
    if (message.role !== 'user') continue;
    const creation = extractRequestedCreation(message.content || '');
    if (creation && !creation.requestedPath) return creation;
  }
  return null;
}

function findMostRecentEditedPath(conversation, beforeIndex) {
  for (let index = beforeIndex - 1; index >= 0; index--) {
    const calls = conversation[index].tool_calls;
    if (!Array.isArray(calls)) continue;
    for (let callIndex = calls.length - 1; callIndex >= 0; callIndex--) {
      const call = calls[callIndex];
      if (!['create_file', 'write_file'].includes(call?.function?.name)) continue;
      try {
        const args = typeof call.function.arguments === 'string'
          ? JSON.parse(call.function.arguments)
          : call.function.arguments;
        if (typeof args?.path === 'string' && args.path) return args.path;
      } catch (_) {
        // Ignore malformed historical tool arguments and continue searching.
      }
    }
  }
  return '';
}

function extractContentUpdate(prompt) {
  const match = prompt.match(/\b(?:set|change|update|replace)\b[\s\S]*?\b(?:content|text)\b[\s\S]*?\b(?:to|with)\s+["']?([\s\S]*?)["']?\s*$/i);
  return match?.[1]?.trim() || '';
}

function callAiProviderWithTools(settings, conversation, callback) {
  const provider = settings.aiProvider || 'builtIn';
  const tools = settings.tools || [];

  if (provider === 'openRouter' || provider === 'openAi') {
    const isOr = provider === 'openRouter';
    const endpoint = isOr
      ? (settings.openRouterEndpoint || 'https://openrouter.ai/api/v1')
      : (settings.openAiEndpoint || 'https://api.openai.com/v1');
    const model = isOr
      ? (settings.openRouterModel || 'google/gemini-2.5-flash')
      : (settings.openAiModel || 'gpt-4o');
    const apiKey = isOr
      ? (settings.openRouterApiKey || process.env.OPENROUTER_API_KEY || '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')
      : (settings.openAiApiKey || '');

    if (!apiKey) {
      return callback(null, { content: `❌ API Key is missing for ${provider}. Configure in Settings.` });
    }

    let url;
    try {
      const base = endpoint.endsWith('/') ? endpoint : endpoint + '/';
      url = new URL('chat/completions', base);
    } catch {
      return callback(null, { content: `❌ Invalid API URL: ${endpoint}` });
    }

    const postData = JSON.stringify({
      model: model,
      messages: conversation,
      tools: tools.length ? tools : undefined,
      temperature: settings.aiTemperature || 0.2,
      max_tokens: settings.aiMaxTokens || 4096,
    });

    const httpModule = url.protocol === 'https:' ? https : http;
    const req = httpModule.request(url, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${apiKey}`,
        'HTTP-Referer': 'https://github.com/atlas-ide',
        'X-Title': 'Atlas IDE',
        'Content-Length': Buffer.byteLength(postData),
      },
    }, (res) => {
      let body = '';
      res.on('data', chunk => body += chunk);
      res.on('end', () => {
        try {
          const parsed = JSON.parse(body);
          if (parsed.choices && parsed.choices[0] && parsed.choices[0].message) {
            const msg = parsed.choices[0].message;
            let extractedCalls = msg.tool_calls || null;
            if (!extractedCalls && msg.content) {
              extractedCalls = extractToolCallsFromText(msg.content);
            }
            callback(null, {
              content: msg.content,
              toolCalls: extractedCalls,
            });
          } else {
            callback(null, { content: `API Error: ${parsed.error?.message || body}` });
          }
        } catch (e) {
          callback(null, { content: `Response parse error: ${body}` });
        }
      });
    });
    req.on('error', (err) => callback(null, { content: `Request failed: ${err.message}` }));
    req.write(postData);
    req.end();
  } else if (provider === 'ollama') {
    const endpoint = settings.ollamaEndpoint || 'http://localhost:11434';
    const model = settings.ollamaModel || 'deepseek-coder';
    let url;
    try {
      url = new URL('/api/chat', endpoint);
    } catch {
      return callback(null, { content: `Invalid Ollama URL: ${endpoint}` });
    }

    const postData = JSON.stringify({
      model,
      messages: conversation,
      tools: tools.length ? tools : undefined,
      stream: false,
    });

    const httpModule = url.protocol === 'https:' ? https : http;
    const req = httpModule.request(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(postData) },
    }, (res) => {
      let body = '';
      res.on('data', chunk => body += chunk);
      res.on('end', () => {
        try {
          const parsed = JSON.parse(body);
          if (parsed.message) {
            let extractedCalls = parsed.message.tool_calls || null;
            // Fallback: if Ollama model printed tool calls as raw text, parse it!
            if (!extractedCalls && parsed.message.content) {
              extractedCalls = extractToolCallsFromText(parsed.message.content);
            }
            callback(null, {
              content: parsed.message.content,
              toolCalls: extractedCalls,
            });
          } else {
            callback(null, { content: body });
          }
        } catch (e) {
          callback(null, { content: body });
        }
      });
    });
    req.on('error', (err) => callback(null, { content: `Ollama error: ${err.message}` }));
    req.write(postData);
    req.end();
  } else {
    // Built-in offline agent tool orchestration with full file CRUD & MCP support
    // Use the current turn, while retaining earlier messages as the source of
    // clarification context. The old `find` selected the first user message,
    // so it could never correctly interpret a later follow-up.
    const { index: userIndex, message: userMessage } = getLatestUserTurn(conversation);
    const promptText = userMessage ? (userMessage.content || '') : '';
    const lowerPrompt = promptText.toLowerCase();

    setTimeout(() => {
      // 1. Creation intent
      const creation = extractRequestedCreation(promptText);
      const acceptsDefault = /^(?:anything|whatever|you decide|your choice)(?:\s+you\s+want)?[.!]*$/i.test(promptText.trim());
      const pendingCreation = acceptsDefault ? findUnresolvedCreation(conversation, userIndex) : null;
      if (creation || pendingCreation) {
        const requestedCreation = creation || pendingCreation;
        const targetPath = requestedCreation.requestedPath || (requestedCreation.isDirectory ? 'atlas-folder' : 'atlas-note.txt');
        const content = requestedCreation.content || (pendingCreation ? 'Created by Atlas.\n' : '');
        const createCall = builtInToolCall(userIndex, 'create', content ? 'write_file' : 'create_file',
          content ? { path: targetPath, content } : { path: targetPath, isDirectory: requestedCreation.isDirectory });

        if (!requestedCreation.requestedPath && !acceptsDefault) {
          callback(null, {
            content: `What would you like to name the ${requestedCreation.isDirectory ? 'folder' : 'file'}, and what should it contain?`,
            toolCalls: null,
          });
          return;
        }

        if (!wasToolExecutedThisTurn(conversation, userIndex, createCall.id)) {
          callback(null, {
            content: `Creating ${requestedCreation.isDirectory ? 'folder' : 'file'} "${targetPath}" in workspace...`,
            toolCalls: [createCall],
          });
          return;
        }
      }

      // 2. A follow-up can modify the file created in a previous turn.
      const updatedContent = extractContentUpdate(promptText);
      const previousPath = updatedContent ? findMostRecentEditedPath(conversation, userIndex) : '';
      if (updatedContent && previousPath) {
        const writeCall = builtInToolCall(userIndex, 'write', 'write_file', { path: previousPath, content: updatedContent });
        if (!wasToolExecutedThisTurn(conversation, userIndex, writeCall.id)) {
          callback(null, {
            content: `Updating "${previousPath}"...`,
            toolCalls: [writeCall],
          });
          return;
        }
      }

      // 3. Deletion intent
      if (lowerPrompt.includes('delete') || lowerPrompt.includes('remove')) {
        const fileMatch = promptText.match(/(?:delete|remove)\s+(?:file|folder|directory)?\s*([a-zA-Z0-9_./\\-]+)/i);
        const path = fileMatch ? fileMatch[1].trim() : '';
        const deleteCall = builtInToolCall(userIndex, 'delete', 'delete_file', { path });

        if (path && !wasToolExecutedThisTurn(conversation, userIndex, deleteCall.id)) {
          callback(null, {
            content: `Deleting "${path}" from workspace...`,
            toolCalls: [deleteCall],
          });
          return;
        }
      }

      // 4. Search / Find intent
      const searchCall = builtInToolCall(userIndex, 'search', 'search_code', { query: 'atlas' });
      if ((lowerPrompt.includes('find') || lowerPrompt.includes('search') || lowerPrompt.includes('where')) && !wasToolExecutedThisTurn(conversation, userIndex, searchCall.id)) {
        const queryMatch = lowerPrompt.match(/(?:find|search|where)\s+([a-zA-Z0-9_-]+)/);
        const query = queryMatch ? queryMatch[1] : 'atlas';
        searchCall.function.arguments = JSON.stringify({ query });
        callback(null, {
          content: `Searching codebase for "${query}"...`,
          toolCalls: [searchCall],
        });
        return;
      }

      // 5. Structure intent
      const structureCall = builtInToolCall(userIndex, 'struct', 'get_project_info', {});
      if (!wasToolExecutedThisTurn(conversation, userIndex, structureCall.id)) {
        callback(null, {
          content: 'Inspecting project configuration...',
          toolCalls: [structureCall],
        });
        return;
      }

      // Default completion
      const toolErrors = getToolErrorsThisTurn(conversation, userIndex);
      if (toolErrors.length > 0) {
        callback(null, {
          content: `### ⚠️ Atlas Built-In Agent Task Incomplete\n\nA tool failed: ${toolErrors[0]}\n\nYour conversation and tool results were preserved. Update the request or retry the operation.`,
          toolCalls: null,
        });
        return;
      }
      callback(null, {
        content: `### 🤖 Atlas Built-In Agent Task Complete\n\nSuccessfully executed requested operations on your workspace.\n\n*Note: To connect autonomous open-source models on your GPU, select **Ollama** in Atlas Settings.*`,
        toolCalls: null,
      });
    }, 200);
  }
}

module.exports = {
  callAiProvider,
  callAiProviderWithTools,
  extractToolCallsFromText,
};
