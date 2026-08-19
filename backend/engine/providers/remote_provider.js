const http = require('http');
const https = require('https');
const { ModelProvider } = require('./base_provider');

class RemoteProvider extends ModelProvider {
  get id() {
    return 'remote';
  }

  get name() {
    return 'Remote / Colab Endpoint';
  }

  get models() {
    return ['custom-model', 'remote-agent'];
  }

  get capabilities() {
    return {
      streaming: true,
      toolCalling: true,
      vision: false,
    };
  }

  async send({ messages, tools = [], options = {}, cancellationToken = null }) {
    const endpoint = this.config.endpoint || 'http://localhost:8000/v1/chat/completions';
    const apiKey = this.config.apiKey || '';
    const model = options.model || this.config.model || 'custom-model';

    const body = {
      model,
      messages,
      temperature: options.temperature ?? this.config.temperature ?? 0.2,
      max_tokens: options.maxTokens ?? this.config.maxTokens ?? 4096,
    };

    if (Array.isArray(tools) && tools.length > 0) {
      body.tools = tools;
    }

    const url = new URL(endpoint);

    return new Promise((resolve, reject) => {
      const postData = JSON.stringify(body);
      let finished = false;

      const headers = {
        'Content-Type': 'application/json',
        'Content-Length': Buffer.byteLength(postData),
      };
      if (apiKey) headers.Authorization = `Bearer ${apiKey}`;

      const req = (url.protocol === 'https:' ? https : http).request(
        url,
        {
          method: 'POST',
          headers,
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
              return reject(new Error(`Remote Endpoint Error (${status}): ${data?.error?.message || raw}`));
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
              content: msg.content || (typeof data === 'string' ? data : data.content || null),
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
            reject(new Error('Remote request cancelled by user'));
          }
        });
      }

      req.on('timeout', () => {
        if (!finished) {
          finished = true;
          req.destroy();
          reject(new Error('Remote endpoint request timed out'));
        }
      });

      req.on('error', (err) => {
        if (!finished) {
          finished = true;
          reject(new Error(`Cannot connect to remote endpoint at ${endpoint}: ${err.message}`));
        }
      });

      req.write(postData);
      req.end();
    });
  }
}

module.exports = {
  RemoteProvider,
};
