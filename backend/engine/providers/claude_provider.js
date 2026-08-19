const https = require('https');
const { ModelProvider } = require('./base_provider');

class ClaudeProvider extends ModelProvider {
  get id() {
    return 'claude';
  }

  get name() {
    return 'Anthropic Claude';
  }

  get models() {
    return [
      'claude-3-7-sonnet-20250219',
      'claude-3-5-sonnet-20241022',
      'claude-3-5-haiku-20241022',
    ];
  }

  get capabilities() {
    return {
      streaming: true,
      toolCalling: true,
      vision: true,
    };
  }

  _formatMessages(messages) {
    let system = '';
    const anthropicMessages = [];

    for (const m of messages) {
      if (m.role === 'system') {
        system += (system ? '\n\n' : '') + (m.content || '');
        continue;
      }

      if (m.role === 'user') {
        anthropicMessages.push({ role: 'user', content: m.content || '' });
      } else if (m.role === 'assistant') {
        const contentBlocks = [];
        if (m.content) contentBlocks.push({ type: 'text', text: m.content });
        if (Array.isArray(m.tool_calls)) {
          for (const tc of m.tool_calls) {
            let input = tc.function?.arguments || tc.args || {};
            if (typeof input === 'string') {
              try { input = JSON.parse(input); } catch (_) { input = {}; }
            }
            contentBlocks.push({
              type: 'tool_use',
              id: tc.id || `toolu_${Date.now()}`,
              name: tc.function?.name || tc.name || '',
              input,
            });
          }
        }
        anthropicMessages.push({ role: 'assistant', content: contentBlocks.length > 0 ? contentBlocks : m.content || '' });
      } else if (m.role === 'tool') {
        anthropicMessages.push({
          role: 'user',
          content: [
            {
              type: 'tool_result',
              tool_use_id: m.tool_call_id || m.id || 'toolu_1',
              content: typeof m.content === 'string' ? m.content : JSON.stringify(m.content),
            },
          ],
        });
      }
    }

    return { system, messages: anthropicMessages };
  }

  _formatTools(tools) {
    if (!Array.isArray(tools) || tools.length === 0) return undefined;
    return tools.map((t) => {
      const func = t.function || t;
      return {
        name: func.name,
        description: func.description,
        input_schema: func.parameters || func.inputSchema || { type: 'object', properties: {} },
      };
    });
  }

  async send({ messages, tools = [], options = {}, cancellationToken = null }) {
    const apiKey = this.config.apiKey || process.env.ANTHROPIC_API_KEY || '';
    if (!apiKey) throw new Error('Anthropic API Key is required.');

    const model = options.model || this.config.model || 'claude-3-5-sonnet-20241022';
    const { system, messages: anthropicMessages } = this._formatMessages(messages);
    const anthropicTools = this._formatTools(tools);

    const body = {
      model,
      messages: anthropicMessages,
      max_tokens: options.maxTokens ?? this.config.maxTokens ?? 4096,
      temperature: options.temperature ?? this.config.temperature ?? 0.2,
    };
    if (system) body.system = system;
    if (anthropicTools) body.tools = anthropicTools;

    const url = new URL('https://api.anthropic.com/v1/messages');

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
            'x-api-key': apiKey,
            'anthropic-version': '2023-06-01',
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
              return reject(new Error(`Anthropic Error (${status}): ${data?.error?.message || raw}`));
            }

            let textContent = '';
            const toolCalls = [];

            if (Array.isArray(data.content)) {
              for (const block of data.content) {
                if (block.type === 'text') textContent += block.text;
                if (block.type === 'tool_use') {
                  toolCalls.push({
                    id: block.id,
                    name: block.name,
                    args: block.input || {},
                  });
                }
              }
            }

            resolve({
              content: textContent || null,
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
          reject(new Error('Claude request timed out'));
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
  ClaudeProvider,
};
