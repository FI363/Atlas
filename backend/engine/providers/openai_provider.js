const https = require('https');
const http = require('http');
const { ModelProvider } = require('./base_provider');

class OpenAIProvider extends ModelProvider {
  get id() {
    return 'openai';
  }

  get name() {
    return 'OpenAI';
  }

  get models() {
    return [
      'gpt-4o',
      'gpt-4o-mini',
      'o1',
      'o3-mini',
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
    const apiKey = this.config.apiKey || process.env.OPENAI_API_KEY || '';
    if (!apiKey) throw new Error('OpenAI API Key is required.');

    const endpoint = this.config.endpoint || 'https://api.openai.com/v1/chat/completions';
    const model = options.model || this.config.model || 'gpt-4o';

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
              return reject(new Error(`OpenAI Error (${status}): ${data?.error?.message || raw}`));
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
          reject(new Error('OpenAI request timed out'));
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
  OpenAIProvider,
};
