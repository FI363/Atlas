const https = require('https');
const http = require('http');
const { ModelProvider } = require('./base_provider');

class GeminiProvider extends ModelProvider {
  get id() {
    return 'gemini';
  }

  get name() {
    return 'Google Gemini';
  }

  get models() {
    return [
      'gemini-2.5-flash',
      'gemini-2.0-flash',
      'gemini-2.0-pro-exp-02-05',
      'gemini-1.5-pro',
    ];
  }

  get capabilities() {
    return {
      streaming: true,
      toolCalling: true,
      vision: true,
    };
  }

  /**
   * Translates standard conversation messages to Gemini contents format.
   */
  _formatContents(messages) {
    let systemText = '';
    const contents = [];

    for (const msg of messages) {
      if (msg.role === 'system') {
        systemText += (systemText ? '\n\n' : '') + (msg.content || '');
        continue;
      }

      if (msg.role === 'user') {
        contents.push({
          role: 'user',
          parts: [{ text: typeof msg.content === 'string' ? msg.content : JSON.stringify(msg.content) }],
        });
      } else if (msg.role === 'assistant') {
        const parts = [];
        if (msg.content) {
          parts.push({ text: msg.content });
        }
        if (Array.isArray(msg.tool_calls)) {
          for (const tc of msg.tool_calls) {
            const funcName = tc.function?.name || tc.name || '';
            let funcArgs = tc.function?.arguments || tc.args || {};
            if (typeof funcArgs === 'string') {
              try { funcArgs = JSON.parse(funcArgs); } catch (_) { funcArgs = {}; }
            }
            parts.push({
              functionCall: {
                name: funcName,
                args: funcArgs,
              },
            });
          }
        }
        if (parts.length === 0) parts.push({ text: '' });
        contents.push({ role: 'model', parts });
      } else if (msg.role === 'tool') {
        // Tool result part
        const funcName = msg.name || 'tool_response';
        let responsePayload = msg.content;
        if (typeof responsePayload === 'string') {
          try { responsePayload = JSON.parse(responsePayload); } catch (_) { responsePayload = { output: responsePayload }; }
        }
        contents.push({
          role: 'user',
          parts: [
            {
              functionResponse: {
                name: funcName,
                response: typeof responsePayload === 'object' && responsePayload !== null ? responsePayload : { output: responsePayload },
              },
            },
          ],
        });
      }
    }

    return { systemText, contents };
  }

  /**
   * Translates standard tool definitions to Gemini functionDeclarations format.
   */
  _formatTools(tools) {
    if (!Array.isArray(tools) || tools.length === 0) return undefined;

    const declarations = [];
    for (const t of tools) {
      if (t.type === 'function' && t.function) {
        declarations.push({
          name: t.function.name,
          description: t.function.description,
          parameters: t.function.parameters,
        });
      } else if (t.name) {
        declarations.push({
          name: t.name,
          description: t.description,
          parameters: t.inputSchema || t.parameters,
        });
      }
    }

    return declarations.length > 0 ? [{ functionDeclarations: declarations }] : undefined;
  }

  /**
   * Executes a standard non-streaming request to Gemini API.
   */
  async send({ messages, tools = [], options = {}, cancellationToken = null }) {
    const apiKey = this.config.apiKey || process.env.GEMINI_API_KEY || '';
    if (!apiKey) {
      throw new Error('Google Gemini API Key is required. Set your API Key in Settings or GEMINI_API_KEY.');
    }

    const model = options.model || this.config.model || 'gemini-2.5-flash';
    const { systemText, contents } = this._formatContents(messages);
    const geminiTools = this._formatTools(tools);

    const body = {
      contents,
      generationConfig: {
        temperature: options.temperature ?? this.config.temperature ?? 0.2,
        maxOutputTokens: options.maxTokens ?? this.config.maxTokens ?? 4096,
      },
    };

    if (systemText) {
      body.systemInstruction = { parts: [{ text: systemText }] };
    }
    if (geminiTools) {
      body.tools = geminiTools;
    }

    const url = new URL(`https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${apiKey}`);

    return new Promise((resolve, reject) => {
      const postData = JSON.stringify(body);
      let finished = false;

      const req = https.request(
        url,
        {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'Content-Length': Buffer.byteLength(postData),
          },
          timeout: 60000,
        },
        (res) => {
          let raw = '';
          res.on('data', (chunk) => (raw += chunk));
          res.on('end', () => {
            if (finished) return;
            finished = true;

            const status = res.statusCode || 200;
            let data;
            try {
              data = JSON.parse(raw);
            } catch {
              data = raw;
            }

            if (status >= 400) {
              const errorMsg = data?.error?.message || `HTTP ${status}: ${raw}`;
              return reject(new Error(`Gemini API Error (${status}): ${errorMsg}`));
            }

            const candidate = data?.candidates?.[0];
            let textContent = '';
            const toolCalls = [];

            if (candidate?.content?.parts) {
              for (const part of candidate.content.parts) {
                if (part.text) {
                  textContent += part.text;
                }
                if (part.functionCall) {
                  toolCalls.push({
                    id: `call_${Date.now()}_${Math.random().toString(36).substring(2, 7)}`,
                    name: part.functionCall.name,
                    args: part.functionCall.args || {},
                  });
                }
              }
            }

            resolve({
              content: textContent || null,
              toolCalls: toolCalls.length > 0 ? toolCalls : [],
              rawResponse: data,
            });
          });
        }
      );

      if (cancellationToken) {
        cancellationToken.onCancelled(() => {
          if (!finished) {
            finished = true;
            req.destroy();
            reject(new Error('Request cancelled by user'));
          }
        });
      }

      req.on('timeout', () => {
        if (!finished) {
          finished = true;
          req.destroy();
          reject(new Error('Gemini request timed out after 60 seconds'));
        }
      });

      req.on('error', (err) => {
        if (!finished) {
          finished = true;
          reject(err);
        }
      });

      req.write(postData);
      req.end();
    });
  }

  /**
   * Executes a streaming request with SSE to Gemini API.
   */
  async stream({ messages, tools = [], options = {}, cancellationToken = null, onToken = null, onToolCall = null }) {
    const apiKey = this.config.apiKey || process.env.GEMINI_API_KEY || '';
    if (!apiKey) {
      throw new Error('Google Gemini API Key is required.');
    }

    const model = options.model || this.config.model || 'gemini-2.5-flash';
    const { systemText, contents } = this._formatContents(messages);
    const geminiTools = this._formatTools(tools);

    const body = {
      contents,
      generationConfig: {
        temperature: options.temperature ?? this.config.temperature ?? 0.2,
        maxOutputTokens: options.maxTokens ?? this.config.maxTokens ?? 4096,
      },
    };

    if (systemText) body.systemInstruction = { parts: [{ text: systemText }] };
    if (geminiTools) body.tools = geminiTools;

    const url = new URL(`https://generativelanguage.googleapis.com/v1beta/models/${model}:streamGenerateContent?alt=sse&key=${apiKey}`);

    return new Promise((resolve, reject) => {
      const postData = JSON.stringify(body);
      let finished = false;
      let fullContent = '';
      const toolCalls = [];

      const req = https.request(
        url,
        {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'Content-Length': Buffer.byteLength(postData),
          },
          timeout: 60000,
        },
        (res) => {
          let buffer = '';

          res.on('data', (chunk) => {
            buffer += chunk.toString();
            const lines = buffer.split(/\r?\n/);
            buffer = lines.pop(); // keep partial trailing line

            for (const line of lines) {
              const trimmed = line.trim();
              if (!trimmed.startsWith('data:')) continue;
              const jsonStr = trimmed.slice(5).trim();
              if (jsonStr === '[DONE]') continue;

              try {
                const parsed = JSON.parse(jsonStr);
                const candidate = parsed?.candidates?.[0];
                if (candidate?.content?.parts) {
                  for (const part of candidate.content.parts) {
                    if (part.text) {
                      fullContent += part.text;
                      if (onToken) onToken(part.text);
                    }
                    if (part.functionCall) {
                      const tc = {
                        id: `call_${Date.now()}_${Math.random().toString(36).substring(2, 7)}`,
                        name: part.functionCall.name,
                        args: part.functionCall.args || {},
                      };
                      toolCalls.push(tc);
                      if (onToolCall) onToolCall(tc);
                    }
                  }
                }
              } catch (_) {}
            }
          });

          res.on('end', () => {
            if (finished) return;
            finished = true;
            resolve({
              content: fullContent,
              toolCalls,
            });
          });
        }
      );

      if (cancellationToken) {
        cancellationToken.onCancelled(() => {
          if (!finished) {
            finished = true;
            req.destroy();
            reject(new Error('Streaming request cancelled by user'));
          }
        });
      }

      req.on('timeout', () => {
        if (!finished) {
          finished = true;
          req.destroy();
          reject(new Error('Stream timed out'));
        }
      });

      req.on('error', (err) => {
        if (!finished) {
          finished = true;
          reject(err);
        }
      });

      req.write(postData);
      req.end();
    });
  }
}

module.exports = {
  GeminiProvider,
};
