const { execFile } = require('child_process');
const https = require('https');

function runGit(args, cwd, callback, options = {}) {
  execFile('git', args, { cwd, ...options }, (err, stdout, stderr) => {
    callback(err, stdout, stderr);
  });
}

function runGitPromise(args, cwd, options = {}) {
  return new Promise((resolve, reject) => {
    execFile('git', args, { cwd, ...options }, (err, stdout, stderr) => {
      if (err) {
        reject(new Error(stderr || stdout || err.message));
      } else {
        resolve(stdout);
      }
    });
  });
}

function callGithubApi(token, method, endpoint, postBody, callback) {
  if (!token) return callback(new Error('GitHub Personal Access Token is required.'));

  let url;
  try {
    url = new URL(endpoint.startsWith('http') ? endpoint : `https://api.github.com${endpoint}`);
  } catch (e) {
    return callback(new Error(`Invalid URL: ${endpoint}`));
  }

  const postData = postBody ? JSON.stringify(postBody) : null;
  const headers = {
    'User-Agent': 'Atlas-IDE-Engine',
    'Accept': 'application/vnd.github.v3+json',
    'Authorization': `Bearer ${token}`,
  };
  if (postData) {
    headers['Content-Type'] = 'application/json';
    headers['Content-Length'] = Buffer.byteLength(postData);
  }

  const req = https.request(url, { method: method, headers: headers }, (res) => {
    let body = '';
    res.on('data', chunk => body += chunk);
    res.on('end', () => {
      try {
        const parsed = JSON.parse(body);
        if (res.statusCode >= 200 && res.statusCode < 300) {
          callback(null, parsed);
        } else {
          callback(new Error(parsed.message || `GitHub API error (${res.statusCode})`));
        }
      } catch (e) {
        callback(e);
      }
    });
  });

  req.on('error', (err) => callback(err));
  if (postData) req.write(postData);
  req.end();
}

function sendGitStatus(ws, workspaceRoot) {
  runGit(['status', '--porcelain'], workspaceRoot, (statusErr, stdout) => {
    runGit(['branch', '--show-current'], workspaceRoot, (branchErr, branchOut) => {
      if (statusErr || branchErr) {
        ws.send(JSON.stringify({
          type: 'error',
          content: `Git status failed: ${(statusErr || branchErr).message}\n`,
        }));
        return;
      }
      const files = (stdout || '').split('\n').filter(Boolean).map(line => {
        const rawStatus = line.substring(0, 2);
        return {
          status: rawStatus.trim(),
          staged: rawStatus[0] !== ' ' && rawStatus[0] !== '?',
          path: line.substring(3).trim(),
        };
      });
      ws.send(JSON.stringify({
        type: 'git_status_result',
        branch: (branchOut || '').trim() || 'HEAD',
        files,
      }));
    });
  });
}

function sendGitDiff(ws, workspaceRoot, filePath, staged = false) {
  if (typeof filePath !== 'string' || !filePath.trim()) {
    ws.send(JSON.stringify({ type: 'error', content: 'Git diff requires a file path.\n' }));
    return;
  }

  const args = ['diff'];
  if (staged) args.push('--staged');
  // `--` treats the following value as a path even when it begins with `-`.
  args.push('--', filePath);
  runGit(args, workspaceRoot, (err, stdout, stderr) => {
    if (err) {
      ws.send(JSON.stringify({
        type: 'error',
        content: `Git diff failed: ${stderr || err.message}\n`,
      }));
      return;
    }
    ws.send(JSON.stringify({
      type: 'git_diff_result',
      path: filePath,
      staged,
      diff: stdout || 'No diff is available for this file. Untracked files must be added before Git can show a patch.',
    }));
  });
}

// Promises for MCP tools
async function getStatus(cwd) {
  const statusOut = await runGitPromise(['status', '--porcelain'], cwd);
  const branchOut = await runGitPromise(['branch', '--show-current'], cwd).catch(() => 'HEAD');
  const files = (statusOut || '').split('\n').filter(Boolean).map(line => {
    const rawStatus = line.substring(0, 2);
    return {
      status: rawStatus.trim(),
      staged: rawStatus[0] !== ' ' && rawStatus[0] !== '?',
      path: line.substring(3).trim(),
    };
  });
  return {
    branch: (branchOut || '').trim() || 'HEAD',
    files,
  };
}

async function getDiff(cwd, options = {}) {
  const args = ['diff'];
  if (options.staged) args.push('--staged');
  if (options.filePath) args.push(options.filePath);
  return await runGitPromise(args, cwd);
}

async function getLog(cwd, maxCount = 10) {
  const stdout = await runGitPromise(['log', `-n${maxCount}`, '--pretty=format:%h|%an|%ar|%s'], cwd);
  return (stdout || '').split('\n').filter(Boolean).map(line => {
    const [hash, author, date, message] = line.split('|');
    return { hash, author, date, message };
  });
}

module.exports = {
  runGit,
  runGitPromise,
  callGithubApi,
  sendGitStatus,
  sendGitDiff,
  getStatus,
  getDiff,
  getLog,
};
