const https = require('https');
const http = require('http');
const { ModelProvider } = require('./base_provider');

class OpenRouterProvider extends ModelProvider {
  get id() {
    return 'openrouter';
  }

  get name() {
    return 'OpenRouter';
  }

  get models() {
    return [
      'google/gemini-2.5-flash',
      'anthropic/claude-3.7-sonnet',
      'deepseek/deepseek-r1',
      'openai/gpt-4o',
      'meta-llama/llama-3.3-70b-instruct',
    ];
  }

  get capabilities() {
    return {
      streaming: true,
      toolCalling: true,
      vision: true,
    };
  }

  async send({ messages, tools = [], options = {}, cancellationToken = null }) {
    const apiKey = this.config.apiKey || process.env.OPENROUTER_API_KEY || '';
    if (!apiKey) {
      throw new Error('OpenRouter API Key is required.');
    }

    const endpoint = this.config.endpoint || 'https://openrouter.ai/api/v1/chat/completions';
    const model = options.model || this.config.model || 'google/gemini-2.5-flash';

    const body = {
      model,
      messages,
      temperature: options.temperature ?? this.config.temperature ?? 0.2,
      max_tokens: options.maxTokens ?? this.config.maxTokens ?? 4096,
    };

    if (Array.isArray(tools) && tools.length > 0) {
      body.tools = tools;
    }

    const url = new URL(endpoint.endsWith('/chat/completions') ? endpoint : `${endpoint.replace(/\/$/, '')}/chat/completions`);

    return new Promise((resolve, reject) => {
      const postData = JSON.stringify(body);
      let finished = false;

      const req = (url.protocol === 'https:' ? https : http).request(
        url,
        {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'Content-Length': Buffer.byteLength(postData),
            Authorization: `Bearer ${apiKey}`,
            'HTTP-Referer': 'https://github.com/atlas-ide',
            'X-Title': 'Atlas IDE',
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
            try { data = JSON.parse(raw); } catch { data = raw; }

            if (status >= 400) {
              const msg = data?.error?.message || `HTTP ${status}: ${raw}`;
              return reject(new Error(`OpenRouter Error (${status}): ${msg}`));
            }

            const choice = data?.choices?.[0];
            const msg = choice?.message || {};
            const toolCalls = [];

            if (Array.isArray(msg.tool_calls)) {
              for (const tc of msg.tool_calls) {
                let args = tc.function?.arguments || {};
                if (typeof args === 'string') {
                  try { args = JSON.parse(args); } catch (_) { args = {}; }
                }
                toolCalls.push({
                  id: tc.id || `call_${Date.now()}`,
                  name: tc.function?.name || '',
                  args,
                });
              }
            }

            resolve({
              content: msg.content || null,
              toolCalls,
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
          reject(new Error('OpenRouter request timed out'));
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

  async stream({ messages, tools = [], options = {}, cancellationToken = null, onToken = null, onToolCall = null }) {
    // Falls back to send if stream is not directly needed, or streams SSE chunks
    return this.send({ messages, tools, options, cancellationToken });
  }
}

module.exports = {
  OpenRouterProvider,
};
