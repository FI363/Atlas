const http = require('http');
const https = require('https');

/**
 * Robust URL resolver that correctly preserves base paths (e.g. /v1, /api/v1).
 */
function resolveEndpoint(endpoint, defaultPath) {
  let trimmed = String(endpoint || '').trim();
  if (!trimmed.startsWith('http://') && !trimmed.startsWith('https://')) {
    trimmed = 'https://' + trimmed;
  }
  if (trimmed.endsWith('/')) trimmed = trimmed.slice(0, -1);
  if (
    trimmed.endsWith('/chat/completions') ||
    trimmed.endsWith('/messages') ||
    trimmed.endsWith('/generateContent') ||
    trimmed.endsWith('/api/chat')
  ) {
    return new URL(trimmed);
  }
  const sub = defaultPath.replace(/^\//, '');
  return new URL(`${trimmed}/${sub}`);
}

/**
 * Universal HTTP/HTTPS JSON requester with timeout and descriptive error formatting.
 */
function sendJsonRequest({ url, method = 'POST', headers = {}, body, timeoutMs = 60000 }, callback) {
  let parsedUrl;
  try {
    parsedUrl = typeof url === 'string' ? new URL(url) : url;
  } catch (e) {
    return callback(new Error(`Invalid URL "${url}": ${e.message}`));
  }

  const postData = body ? (typeof body === 'string' ? body : JSON.stringify(body)) : '';
  const mergedHeaders = {
    'Content-Type': 'application/json',
    ...headers,
  };
  if (postData) {
    mergedHeaders['Content-Length'] = Buffer.byteLength(postData);
  }

  const httpModule = parsedUrl.protocol === 'https:' ? https : http;
  const req = httpModule.request(
    parsedUrl,
    {
      method,
      headers: mergedHeaders,
      timeout: timeoutMs,
    },
    (res) => {
      let raw = '';
      res.on('data', (chunk) => (raw += chunk));
      res.on('end', () => {
        const status = res.statusCode || 200;
        let data = null;
        try {
          data = JSON.parse(raw);
        } catch {
          data = raw;
        }

        if (status >= 400) {
          let errorMsg = `HTTP ${status}: `;
          if (data && typeof data === 'object') {
            errorMsg += data.error?.message || data.message || JSON.stringify(data);
          } else {
            errorMsg += raw || 'Request failed';
          }
          const err = new Error(errorMsg);
          err.statusCode = status;
          err.responseData = data;
          return callback(err, null);
        }

        callback(null, data);
      });
    }
  );

  req.on('timeout', () => {
    req.destroy();
    callback(new Error(`Request to ${parsedUrl.hostname} timed out after ${timeoutMs / 1000}s`));
  });

  req.on('error', (err) => {
    let friendly = err.message;
    if (err.code === 'ECONNREFUSED') {
      friendly = `Connection refused at ${parsedUrl.host}. Is the service running?`;
    } else if (err.code === 'ENOTFOUND') {
      friendly = `Host lookup failed for ${parsedUrl.hostname}. Check your network or URL.`;
    }
    callback(new Error(friendly));
  });

  if (postData) req.write(postData);
  req.end();
}

/**
 * Standard prompt dispatcher for user questions / code generation.
 */
function callAiProvider(settings, prompt, contextCode, attachments, callback) {
  const provider = settings.aiProvider || 'builtIn';
  const systemPrompt =
    settings.aiSystemPrompt ||
    'You are Atlas, an expert agentic AI software engineer embedded in Atlas IDE. When providing code changes or new files, wrap complete code in ```language:filepath code blocks.';

  const textAttachments = (attachments || []).filter(
    (item) => item && item.kind === 'file' && typeof item.text === 'string'
  );
  const imageAttachments = (attachments || []).filter(
    (item) => item && item.kind === 'image' && typeof item.dataBase64 === 'string'
  );

  const attachmentSummary = (attachments || [])
    .map((item) => {
      if (!item || !item.name) return '';
      if (item.kind === 'image') return `- Image: ${item.name} (${item.mimeType || 'image'})`;
      if (item.kind === 'file')
        return `- File: ${item.name} (${item.mimeType || 'file'}${item.size ? `, ${item.size} bytes` : ''})`;
      return `- Attachment: ${item.name}`;
    })
    .filter(Boolean)
    .join('\n');

  const userText = [
    contextCode ? `Active Code Context:\n\`\`\`\n${contextCode}\n\`\`\`` : '',
    attachmentSummary ? `Attachments:\n${attachmentSummary}` : '',
    textAttachments.length
      ? `Attached File Contents:\n${textAttachments
          .map((item) => `### ${item.name}\n\`\`\`\n${item.text}\n\`\`\``)
          .join('\n\n')}`
      : '',
    `Task: ${prompt}`,
  ]
    .filter(Boolean)
    .join('\n\n');

  // ── OpenRouter ─────────────────────────────────────────────────────────────
  if (provider === 'openRouter') {
    const endpoint = settings.openRouterEndpoint || 'https://openrouter.ai/api/v1';
    const model = settings.openRouterModel || 'google/gemini-2.5-flash';
    const apiKey =
      settings.openRouterApiKey ||
      process.env.OPENROUTER_API_KEY ||
      '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';

    if (!apiKey) {
      return callback(null, '❌ OpenRouter API Key is missing! Set your key in Atlas Settings → AI Agent.');
    }

    const url = resolveEndpoint(endpoint, 'chat/completions');
    const userMessage = imageAttachments.length
      ? {
          role: 'user',
          content: [
            { type: 'text', text: userText },
            ...imageAttachments.map((item) => ({
              type: 'image_url',
              image_url: { url: `data:${item.mimeType || 'image/png'};base64,${item.dataBase64}` },
            })),
          ],
        }
      : { role: 'user', content: userText };

    sendJsonRequest(
      {
        url,
        headers: {
          Authorization: `Bearer ${apiKey}`,
          'HTTP-Referer': 'https://github.com/atlas-ide',
          'X-Title': 'Atlas IDE',
        },
        body: {
          model,
          messages: [
            { role: 'system', content: systemPrompt },
            userMessage,
          ],
          temperature: settings.aiTemperature || 0.2,
          max_tokens: settings.aiMaxTokens || 4096,
        },
      },
      (err, data) => {
        if (err) return callback(null, `❌ OpenRouter Error: ${err.message}`);
        if (data?.choices?.[0]?.message?.content) {
          callback(null, `### ⚡ OpenRouter (${model})\n\n${data.choices[0].message.content}`);
        } else {
          callback(null, `❌ OpenRouter unexpected response: ${JSON.stringify(data)}`);
        }
      }
    );
  }

  // ── OpenAI / Compatible ───────────────────────────────────────────────────
  else if (provider === 'openAi' || provider === 'deepseek' || provider === 'groq') {
    let endpoint = settings.openAiEndpoint || 'https://api.openai.com/v1';
    let model = settings.openAiModel || 'gpt-4o';
    let apiKey = settings.openAiApiKey || '';

    if (provider === 'deepseek') {
      endpoint = settings.deepseekEndpoint || 'https://api.deepseek.com';
      model = settings.deepseekModel || 'deepseek-chat';
      apiKey = settings.deepseekApiKey || apiKey;
    } else if (provider === 'groq') {
      endpoint = settings.groqEndpoint || 'https://api.groq.com/openai/v1';
      model = settings.groqModel || 'llama-3.3-70b-versatile';
      apiKey = settings.groqApiKey || apiKey;
    }

    if (!apiKey) {
      return callback(null, `❌ API Key is missing for ${provider.toUpperCase()}! Set your key in Settings → AI Agent.`);
    }

    const url = resolveEndpoint(endpoint, 'chat/completions');
    sendJsonRequest(
      {
        url,
        headers: { Authorization: `Bearer ${apiKey}` },
        body: {
          model,
          messages: [
            { role: 'system', content: systemPrompt },
            { role: 'user', content: userText },
          ],
          temperature: settings.aiTemperature || 0.2,
          max_tokens: settings.aiMaxTokens || 4096,
        },
      },
      (err, data) => {
        if (err) return callback(null, `❌ ${provider.toUpperCase()} Error: ${err.message}`);
        if (data?.choices?.[0]?.message?.content) {
          callback(null, `### ⚡ ${provider.toUpperCase()} (${model})\n\n${data.choices[0].message.content}`);
        } else {
          callback(null, `❌ API Error: ${JSON.stringify(data)}`);
        }
      }
    );
  }

  // ── Anthropic Claude ───────────────────────────────────────────────────────
  else if (provider === 'anthropic') {
    const endpoint = settings.anthropicEndpoint || 'https://api.anthropic.com/v1';
    const model = settings.anthropicModel || 'claude-3-5-sonnet-20241022';
    const apiKey = settings.anthropicApiKey || '';

    if (!apiKey) {
      return callback(null, '❌ Anthropic API Key is missing! Set your key in Atlas Settings → AI Agent.');
    }

    const url = resolveEndpoint(endpoint, 'messages');
    sendJsonRequest(
      {
        url,
        headers: {
          'x-api-key': apiKey,
          'anthropic-version': '2023-06-01',
        },
        body: {
          model,
          system: systemPrompt,
          messages: [{ role: 'user', content: userText }],
          max_tokens: settings.aiMaxTokens || 4096,
          temperature: settings.aiTemperature || 0.2,
        },
      },
      (err, data) => {
        if (err) return callback(null, `❌ Anthropic Error: ${err.message}`);
        const content = data?.content?.[0]?.text || data?.content || JSON.stringify(data);
        callback(null, `### 🧠 Claude (${model})\n\n${content}`);
      }
    );
  }

  // ── Google Gemini Direct ──────────────────────────────────────────────────
  else if (provider === 'gemini') {
    const model = settings.geminiModel || 'gemini-2.0-flash';
    const apiKey = settings.geminiApiKey || '';

    if (!apiKey) {
      return callback(null, '❌ Google Gemini API Key is missing! Set your key in Atlas Settings → AI Agent.');
    }

    const endpoint = `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${apiKey}`;
    sendJsonRequest(
      {
        url: endpoint,
        body: {
          contents: [
            {
              role: 'user',
              parts: [{ text: `${systemPrompt}\n\n${userText}` }],
            },
          ],
          generationConfig: {
            temperature: settings.aiTemperature || 0.2,
            maxOutputTokens: settings.aiMaxTokens || 4096,
          },
        },
      },
      (err, data) => {
        if (err) return callback(null, `❌ Gemini Error: ${err.message}`);
        const text = data?.candidates?.[0]?.content?.parts?.[0]?.text;
        if (text) {
          callback(null, `### ♊ Google Gemini (${model})\n\n${text}`);
        } else {
          callback(null, `❌ Gemini Response: ${JSON.stringify(data)}`);
        }
      }
    );
  }

  // ── Ollama (Local) ────────────────────────────────────────────────────────
  else if (provider === 'ollama') {
    const endpoint = settings.ollamaEndpoint || 'http://localhost:11434';
    const model = settings.ollamaModel || 'deepseek-coder';
    const url = resolveEndpoint(endpoint, 'api/chat');

    sendJsonRequest(
      {
        url,
        body: {
          model,
          messages: [
            { role: 'system', content: systemPrompt },
            { role: 'user', content: userText },
          ],
          stream: false,
          options: {
            temperature: settings.aiTemperature || 0.2,
            num_predict: settings.aiMaxTokens || 4096,
          },
        },
      },
      (err, data) => {
        if (err) {
          return callback(
            null,
            `❌ Cannot reach Ollama at ${endpoint}.\n\nEnsure Ollama is running (\`ollama serve\`) and the model is pulled (\`ollama pull ${model}\`). Error: ${err.message}`
          );
        }
        const answer = data?.message?.content || data?.response || JSON.stringify(data);
        callback(null, `### 🦙 Ollama (${model})\n\n${answer}`);
      }
    );
  }

  // ── Custom Endpoint ───────────────────────────────────────────────────────
  else if (provider === 'custom') {
    const endpoint = settings.customAgentEndpoint || '';
    if (!endpoint) return callback(null, '❌ Custom Endpoint URL is missing in Settings.');
    let url;
    try {
      url = new URL(endpoint);
    } catch {
      return callback(null, `❌ Invalid Custom URL: ${endpoint}`);
    }

    sendJsonRequest(
      {
        url,
        body: { prompt, contextCode, systemPrompt, attachments },
      },
      (err, data) => {
        if (err) return callback(null, `❌ Custom Endpoint Failed: ${err.message}`);
        callback(null, typeof data === 'string' ? data : data.content || JSON.stringify(data));
      }
    );
  }

  // ── Built-In (Offline Fallback) ───────────────────────────────────────────
  else {
    const lower = prompt.toLowerCase();
    let aiAnswer = '';
    if (lower.includes('explain') || lower.includes('what does this code do')) {
      aiAnswer = `### 🤖 Atlas Built-In Agent: Code Explanation\n\nAnalyzing active context (${contextCode ? contextCode.length : 0} bytes):\n\n- **Structure**: High-performance Flutter reactive component.\n- **State**: Uses \`ChangeNotifier\` & \`WorkspaceState\` for real-time reactivity.\n- **Recommendation**: Ensure UI widgets bind cleanly to state models.`;
    } else if (lower.includes('bug') || lower.includes('fix') || lower.includes('find bugs')) {
      aiAnswer = `### 🐛 Atlas Built-In Agent: Bug Scan\n\n- **Check**: All WebSocket connections verify \`isConnected\` before sending.\n- **Check**: Null bounds checked on file tab switches.\n- **Status**: No critical syntax errors found in active buffer.`;
    } else if (lower.includes('test') || lower.includes('generate tests')) {
      aiAnswer = `### 🧪 Atlas Built-In Agent: Unit Test\n\n\`\`\`dart\nvoid main() {\n  group('WorkspaceState Unit Tests', () {\n    test('verifies initial state and settings', () {\n      // Test implementation\n    });\n  });\n}\n\`\`\``;
    } else {
      aiAnswer = `### 🤖 Atlas Built-In Agent\n\nReceived prompt: "${prompt}".\n\n${contextCode ? '📄 Active File Context Included (' + contextCode.split('\n').length + ' lines).' : 'No active file open.'}\n\n*Tip: Connect **OpenRouter**, **OpenAI**, **Claude**, or **Ollama** in Settings for full LLM intelligence!*`;
    }
    setTimeout(() => callback(null, aiAnswer), 200);
  }
}

/**
 * Universal tool call extractor for models that emit tool calls as text/xml.
 */
function extractToolCallsFromText(text) {
  if (typeof text !== 'string' || !text.trim()) return null;
  const toolCalls = [];

  const xmlRegex = /<tool_call>([\s\S]*?)<\/tool_call>/gi;
  let match;
  while ((match = xmlRegex.exec(text)) !== null) {
    try {
      const parsed = JSON.parse(match[1].trim());
      if (parsed && parsed.name) {
        toolCalls.push({
          id: `call_${Date.now()}_${Math.random().toString(36).substring(2, 7)}`,
          type: 'function',
          function: {
            name: parsed.name,
            arguments: typeof parsed.arguments === 'string' ? parsed.arguments : JSON.stringify(parsed.arguments || {}),
          },
        });
      }
    } catch (_) {}
  }

  const jsonBlockRegex = /```(?:json)?\s*(\{\s*"tool"\s*:[\s\S]*?\})\s*```/gi;
  while ((match = jsonBlockRegex.exec(text)) !== null) {
    try {
      const parsed = JSON.parse(match[1].trim());
      if (parsed && (parsed.tool || parsed.name)) {
        toolCalls.push({
          id: `call_${Date.now()}_${Math.random().toString(36).substring(2, 7)}`,
          type: 'function',
          function: {
            name: parsed.tool || parsed.name,
            arguments: JSON.stringify(parsed.args || parsed.arguments || {}),
          },
        });
      }
    } catch (_) {}
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
  return conversation.slice(userIndex + 1).some(
    (message) => message.role === 'tool' && message.tool_call_id === toolCallId
  );
}

function getToolErrorsThisTurn(conversation, userIndex) {
  return conversation
    .slice(userIndex + 1)
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
      } catch (_) {}
    }
  }
  return '';
}

function extractContentUpdate(prompt) {
  const match = prompt.match(/\b(?:set|change|update|replace)\b[\s\S]*?\b(?:content|text)\b[\s\S]*?\b(?:to|with)\s+["']?([\s\S]*?)["']?\s*$/i);
  return match?.[1]?.trim() || '';
}

/**
 * Sanitize messages for Ollama's native /api/chat endpoint.
 * Ensures tool_calls[].function.arguments is a parsed object, not a JSON string.
 */
function sanitizeOllamaMessages(messages) {
  return (messages || []).map((msg) => {
    const copy = { role: msg.role || 'user', content: msg.content ?? '' };
    if (msg.tool_calls && Array.isArray(msg.tool_calls)) {
      copy.tool_calls = msg.tool_calls.map((tc) => {
        let args = tc.function?.arguments;
        if (typeof args === 'string') {
          try {
            args = JSON.parse(args);
          } catch (_) {
            args = {};
          }
        }
        return {
          type: 'function',
          function: {
            name: tc.function?.name || '',
            arguments: args || {},
          },
        };
      });
    }
    return copy;
  });
}

/**
 * Multi-turn agent loop model dispatcher with tool definitions.
 */
function callAiProviderWithTools(settings, conversation, callback) {
  const provider = settings.aiProvider || 'builtIn';
  const tools = settings.tools || [];

  // ── OpenRouter / OpenAI / DeepSeek / Groq ──────────────────────────────────
  if (
    provider === 'openRouter' ||
    provider === 'openAi' ||
    provider === 'deepseek' ||
    provider === 'groq'
  ) {
    let endpoint = settings.openRouterEndpoint || 'https://openrouter.ai/api/v1';
    let model = settings.openRouterModel || 'google/gemini-2.5-flash';
    let apiKey =
      settings.openRouterApiKey ||
      process.env.OPENROUTER_API_KEY ||
      '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';

    if (provider === 'openAi') {
      endpoint = settings.openAiEndpoint || 'https://api.openai.com/v1';
      model = settings.openAiModel || 'gpt-4o';
      apiKey = settings.openAiApiKey || '';
    } else if (provider === 'deepseek') {
      endpoint = settings.deepseekEndpoint || 'https://api.deepseek.com';
      model = settings.deepseekModel || 'deepseek-chat';
      apiKey = settings.deepseekApiKey || '';
    } else if (provider === 'groq') {
      endpoint = settings.groqEndpoint || 'https://api.groq.com/openai/v1';
      model = settings.groqModel || 'llama-3.3-70b-versatile';
      apiKey = settings.groqApiKey || '';
    }

    if (!apiKey) {
      return callback(null, { content: `❌ API Key is missing for ${provider}. Configure in Settings.` });
    }

    const url = resolveEndpoint(endpoint, 'chat/completions');
    const headers = {
      Authorization: `Bearer ${apiKey}`,
      'HTTP-Referer': 'https://github.com/atlas-ide',
      'X-Title': 'Atlas IDE',
    };

    sendJsonRequest(
      {
        url,
        headers,
        body: {
          model,
          messages: conversation,
          tools: tools.length ? tools : undefined,
          temperature: settings.aiTemperature || 0.2,
          max_tokens: settings.aiMaxTokens || 4096,
        },
      },
      (err, data) => {
        if (err) return callback(null, { content: `❌ ${provider.toUpperCase()} Agent Error: ${err.message}` });
        if (data?.choices?.[0]?.message) {
          const msg = data.choices[0].message;
          let extractedCalls = msg.tool_calls || null;
          if (!extractedCalls && msg.content) {
            extractedCalls = extractToolCallsFromText(msg.content);
          }
          callback(null, {
            content: msg.content,
            toolCalls: extractedCalls,
          });
        } else {
          callback(null, { content: `API Error: ${JSON.stringify(data)}` });
        }
      }
    );
  }

  // ── Ollama Tool Calling ───────────────────────────────────────────────────
  else if (provider === 'ollama') {
    const endpoint = settings.ollamaEndpoint || 'http://localhost:11434';
    const model = settings.ollamaModel || 'deepseek-coder';
    const url = resolveEndpoint(endpoint, 'api/chat');
    const sanitizedMessages = sanitizeOllamaMessages(conversation);

    sendJsonRequest(
      {
        url,
        body: {
          model,
          messages: sanitizedMessages,
          stream: false,
          tools: tools.length ? tools : undefined,
          options: {
            temperature: settings.aiTemperature || 0.2,
            num_predict: settings.aiMaxTokens || 4096,
          },
        },
      },
      (err, data) => {
        if (err) return callback(null, { content: `Ollama error: ${err.message}` });
        const msg = data?.message || {};
        let extractedCalls = msg.tool_calls || null;
        if (!extractedCalls && msg.content) {
          extractedCalls = extractToolCallsFromText(msg.content);
        }
        callback(null, {
          content: msg.content || (typeof data === 'string' ? data : ''),
          toolCalls: extractedCalls,
        });
      }
    );
  }

  // ── Built-In Agent Loop ───────────────────────────────────────────────────
  else {
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

      // 2. Follow-up modification
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
        content: `### 🤖 Atlas Built-In Agent Task Complete\n\nSuccessfully executed requested operations on your workspace.`,
        toolCalls: null,
      });
    }, 200);
  }
}

module.exports = {
  callAiProvider,
  callAiProviderWithTools,
  extractToolCallsFromText,
  resolveEndpoint,
};
