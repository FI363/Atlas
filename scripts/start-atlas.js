const { spawn } = require('child_process');
const path = require('path');
const crypto = require('crypto');
const { freePort, killProcessTree } = require('./port-utils');

const mode = process.argv[2] || 'dev';
if (mode !== 'dev' && mode !== 'ipad' && mode !== 'prod') {
  console.error('Usage: node scripts/start-atlas.js <dev|ipad|prod>');
  process.exit(1);
}

const isLan = mode === 'ipad' || mode === 'prod';
const token = process.env.ATLAS_ENGINE_TOKEN || crypto.randomBytes(32).toString('base64url');
const host = isLan ? '0.0.0.0' : '127.0.0.1';
const flutterHost = isLan ? '0.0.0.0' : 'localhost';
const flutterPort = process.env.ATLAS_WEB_PORT || '8081';
const enginePort = process.env.PORT || '8080';
const childEnv = { ...process.env, ATLAS_ENGINE_TOKEN: token, ATLAS_ENGINE_HOST: host, PORT: String(enginePort) };
const root = path.resolve(__dirname, '..');

console.log(`Starting Atlas in ${isLan ? 'LAN' : 'local'} mode.`);
if (!process.env.ATLAS_ENGINE_TOKEN) {
  console.log('Generated a temporary engine token for this session.');
}

// ── 1. Proactively free required ports before launch ─────────────────────────
console.log('Checking and freeing ports 8080 & 8081...');
freePort(enginePort);
freePort(flutterPort);

let stopping = false;
let engine;
let flutter;

function stop(exitCode = 0) {
  if (stopping) return;
  stopping = true;
  console.log('\nStopping Atlas and releasing ports...');

  killProcessTree(engine);
  killProcessTree(flutter);

  freePort(enginePort);
  freePort(flutterPort);

  process.exit(exitCode);
}

function attachProcessHandlers(child, label) {
  child.on('error', (error) => {
    console.error(`Unable to start Atlas ${label}: ${error.code || error.name}: ${error.message}`);
    stop(1);
  });
  child.on('exit', (code) => {
    if (!stopping && code !== 0) {
      stop(code || 0);
    }
  });
  return child;
}

// ── 2. Start Engine ──────────────────────────────────────────────────────────
engine = attachProcessHandlers(
  spawn(process.execPath, [path.join(root, 'backend', 'server.js')], {
    cwd: root,
    env: childEnv,
    stdio: 'inherit',
  }),
  'engine'
);

const flutterArgs = [
  'run',
  '-d',
  'web-server',
  '--web-hostname',
  flutterHost,
  '--web-port',
  String(flutterPort),
  `--dart-define=ATLAS_ENGINE_TOKEN=${token}`,
];

// ── 3. Start Flutter ─────────────────────────────────────────────────────────
if (process.platform === 'win32') {
  const comspec = process.env.ComSpec || 'cmd.exe';
  flutter = attachProcessHandlers(
    spawn(comspec, ['/d', '/s', '/c', 'flutter.bat', ...flutterArgs], {
      cwd: root,
      env: childEnv,
      stdio: 'inherit',
      windowsHide: true,
    }),
    'Flutter'
  );
} else {
  flutter = attachProcessHandlers(
    spawn('flutter', flutterArgs, {
      cwd: root,
      env: childEnv,
      stdio: 'inherit',
    }),
    'Flutter'
  );
}

// ── 4. Process Exit & Signal Handlers ────────────────────────────────────────
process.on('SIGINT', () => stop(0));
process.on('SIGTERM', () => stop(0));
process.on('exit', () => {
  killProcessTree(engine);
  killProcessTree(flutter);
  freePort(enginePort);
  freePort(flutterPort);
});
