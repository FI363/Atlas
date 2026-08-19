const http = require('http');
const { ModelProvider } = require('./base_provider');

class LocalProvider extends ModelProvider {
  get id() {
    return 'local';
  }

  get name() {
    return 'Local Model (Ollama / On-Device)';
  }

  get models() {
    return [
      'deepseek-coder',
      'qwen2.5-coder',
      'llama3.2',
      'smollm3',
    ];
  }

  get capabilities() {
    return {
      streaming: true,
      toolCalling: true,
      vision: false,
    };
  }

  async send({ messages, tools = [], options = {}, cancellationToken = null }) {
    const endpoint = this.config.endpoint || 'http://localhost:11434/api/chat';
    const model = options.model || this.config.model || 'deepseek-coder';

    const body = {
      model,
      messages,
      stream: false,
      options: {
        temperature: options.temperature ?? this.config.temperature ?? 0.2,
        num_predict: options.maxTokens ?? this.config.maxTokens ?? 4096,
      },
    };

    if (Array.isArray(tools) && tools.length > 0) {
      body.tools = tools;
    }

    const url = new URL(endpoint.endsWith('/api/chat') ? endpoint : `${endpoint.replace(/\/$/, '')}/api/chat`);

    return new Promise((resolve, reject) => {
      const postData = JSON.stringify(body);
      let finished = false;

      const req = http.request(
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
            try { data = JSON.parse(raw); } catch { data = raw; }

            if (status >= 400) {
              return reject(new Error(`Ollama Error (${status}): ${data?.error || raw}`));
            }

            const msg = data?.message || {};
            const toolCalls = [];

            if (Array.isArray(msg.tool_calls)) {
              for (const tc of msg.tool_calls) {
                toolCalls.push({
                  id: tc.id || `call_${Date.now()}`,
                  name: tc.function?.name || '',
                  args: tc.function?.arguments || {},
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
          reject(new Error('Local inference timed out. Is Ollama running?'));
        }
      });

      req.on('error', (err) => {
        if (!finished) {
          finished = true;
          reject(new Error(`Cannot connect to local model at ${endpoint}: ${err.message}`));
        }
      });

      req.write(postData);
      req.end();
    });
  }
}

module.exports = {
  LocalProvider,
};
