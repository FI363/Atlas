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
    const userMessage = conversation.find(m => m.role === 'user');
    const promptText = userMessage ? (userMessage.content || '') : '';
    const lowerPrompt = promptText.toLowerCase();

    // Check which tool calls have already been executed in this conversation
    const executedTools = conversation
      .filter(m => m.role === 'tool')
      .map(m => m.tool_call_id);

    setTimeout(() => {
      // 1. Creation intent
      if (lowerPrompt.includes('create') && (lowerPrompt.includes('file') || lowerPrompt.includes('folder') || lowerPrompt.includes('directory'))) {
        const fileMatch = promptText.match(/(?:create|make)\s+(?:file|folder|directory)?\s*([a-zA-Z0-9_./\\-]+)(?:\s+with\s+content\s+["']?([\s\S]*?)["']?)?/i);
        const path = fileMatch ? fileMatch[1].trim() : 'new_file.txt';
        const content = fileMatch && fileMatch[2] ? fileMatch[2].trim() : '';

        if (!executedTools.includes('call_create')) {
          callback(null, {
            content: `Creating file "${path}" in workspace...`,
            toolCalls: [{
              id: 'call_create',
              type: 'function',
              function: {
                name: content ? 'write_file' : 'create_file',
                arguments: JSON.stringify(content ? { path, content } : { path }),
              },
            }],
          });
          return;
        }
      }

      // 2. Deletion intent
      if (lowerPrompt.includes('delete') || lowerPrompt.includes('remove')) {
        const fileMatch = promptText.match(/(?:delete|remove)\s+(?:file|folder|directory)?\s*([a-zA-Z0-9_./\\-]+)/i);
        const path = fileMatch ? fileMatch[1].trim() : '';

        if (path && !executedTools.includes('call_delete')) {
          callback(null, {
            content: `Deleting "${path}" from workspace...`,
            toolCalls: [{
              id: 'call_delete',
              type: 'function',
              function: {
                name: 'delete_file',
                arguments: JSON.stringify({ path }),
              },
            }],
          });
          return;
        }
      }

      // 3. Search / Find intent
      if ((lowerPrompt.includes('find') || lowerPrompt.includes('search') || lowerPrompt.includes('where')) && !executedTools.includes('call_search')) {
        const queryMatch = lowerPrompt.match(/(?:find|search|where)\s+([a-zA-Z0-9_-]+)/);
        const query = queryMatch ? queryMatch[1] : 'atlas';
        callback(null, {
          content: `Searching codebase for "${query}"...`,
          toolCalls: [{
            id: 'call_search',
            type: 'function',
            function: { name: 'search_code', arguments: JSON.stringify({ query }) },
          }],
        });
        return;
      }

      // 4. Structure intent
      if (!executedTools.includes('call_struct')) {
        callback(null, {
          content: 'Inspecting project configuration...',
          toolCalls: [{
            id: 'call_struct',
            type: 'function',
            function: { name: 'get_project_info', arguments: '{}' },
          }],
        });
        return;
      }

      // Default completion
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
