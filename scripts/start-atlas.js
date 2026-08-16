const { spawn } = require('child_process');
const path = require('path');
const crypto = require('crypto');

const mode = process.argv[2];
if (mode !== 'dev' && mode !== 'ipad' && mode !== 'prod') {
  console.error('Usage: node scripts/start-atlas.js <dev|ipad|prod>');
  process.exit(1);
}

const isLan = mode === 'ipad' || mode === 'prod';
const token = process.env.ATLAS_ENGINE_TOKEN || crypto.randomBytes(32).toString('base64url');
const host = isLan ? '0.0.0.0' : '127.0.0.1';
const flutterHost = isLan ? '0.0.0.0' : 'localhost';
const flutterPort = process.env.ATLAS_WEB_PORT || '8081';
const childEnv = { ...process.env, ATLAS_ENGINE_TOKEN: token, ATLAS_ENGINE_HOST: host };
const root = path.resolve(__dirname, '..');

console.log(`Starting Atlas in ${isLan ? 'LAN' : 'local'} mode.`);
if (!process.env.ATLAS_ENGINE_TOKEN) {
  console.log('Generated a temporary engine token for this session.');
}

let stopping = false;
let engine;
let flutter;

function stop(exitCode = 0) {
  if (stopping) return;
  stopping = true;
  engine?.kill();
  flutter?.kill();
  process.exit(exitCode);
}

function attachProcessHandlers(child, label) {
  child.on('error', (error) => {
    console.error(`Unable to start Atlas ${label}: ${error.code || error.name}: ${error.message}`);
    stop(1);
  });
  child.on('exit', (code) => stop(code || 0));
  return child;
}

// Fix: Use process.execPath for engine to avoid EINVAL on Windows
engine = attachProcessHandlers(spawn(process.execPath, ['backend/server.js'], {
  cwd: root,
  env: childEnv,
  stdio: 'inherit',
}), 'engine');

const flutterArgs = [
  'run', '-d', 'web-server',
  '--web-hostname', flutterHost,
  '--web-port', flutterPort,
  `--dart-define=ATLAS_ENGINE_TOKEN=${token}`,
];

// Fix: On Windows, use cmd.exe to run flutter.bat to avoid EINVAL
if (process.platform === 'win32') {
  const comspec = process.env.ComSpec || 'cmd.exe';
  flutter = attachProcessHandlers(spawn(comspec, ['/d', '/s', '/c', 'flutter.bat', ...flutterArgs], {
    cwd: root,
    env: childEnv,
    stdio: 'inherit',
    windowsHide: true,
  }), 'Flutter');
} else {
  flutter = attachProcessHandlers(spawn('flutter', flutterArgs, {
    cwd: root,
    env: childEnv,
    stdio: 'inherit',
  }), 'Flutter');
}

process.on('SIGINT', () => stop());
process.on('SIGTERM', () => stop());
