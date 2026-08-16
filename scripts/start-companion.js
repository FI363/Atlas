const { spawn } = require('child_process');
const path = require('path');
const os = require('os');
const { startTunnel } = require('untun');
const { freePort, killProcessTree } = require('./port-utils');

// Configuration
const PORT = process.env.PORT ? parseInt(process.env.PORT, 10) : 8080;
const HOST = process.env.ATLAS_ENGINE_HOST || '0.0.0.0';
const TOKEN = process.env.ATLAS_ENGINE_TOKEN || 'atlas-secret-token-12345';
const root = path.resolve(__dirname, '..');

// Clean port before starting
freePort(PORT);

function getLocalIpAddresses() {
  const interfaces = os.networkInterfaces();
  const addresses = [];
  for (const name of Object.keys(interfaces)) {
    for (const net of interfaces[name]) {
      if (net.family === 'IPv4' && !net.internal) {
        addresses.push({ interface: name, address: net.address });
      }
    }
  }
  return addresses;
}

console.log('======================================================');
console.log('🚀 ATLAS COMPANION SERVER FOR IPAD / REMOTE IDE');
console.log('======================================================');
console.log(`🔒 Pairing Token: ${TOKEN}`);
console.log(`⚡ Engine Host:   ${HOST}:${PORT}`);
console.log('');
console.log('📡 Local Wi-Fi Connection Endpoints:');
for (const ip of getLocalIpAddresses()) {
  console.log(`   • ${ip.interface}: ws://${ip.address}:${PORT}`);
}
console.log('======================================================\n');

// 1. Launch Engine Server
const env = {
  ...process.env,
  ATLAS_ENGINE_HOST: HOST,
  ATLAS_ENGINE_TOKEN: TOKEN,
  PORT: String(PORT),
};

const engineProcess = spawn(process.execPath, [path.join(root, 'backend', 'server.js')], {
  cwd: root,
  env,
  stdio: 'inherit',
});

engineProcess.on('exit', (code) => {
  console.log(`[Engine] Server process stopped (code ${code}).`);
  freePort(PORT);
  process.exit(code || 0);
});

// 2. Start Cloudflare Tunnel for secure over-the-air pairing
async function launchTunnel() {
  try {
    console.log('🌐 Starting Cloudflare Quick Tunnel for remote iPad access...');
    const tunnel = await startTunnel({
      port: PORT,
      hostname: '127.0.0.1',
      protocol: 'http',
    });

    if (tunnel) {
      const httpUrl = await tunnel.getURL();
      const wsUrl = httpUrl.replace(/^http/, 'ws');
      console.log('\n======================================================');
      console.log('✨ REMOTE CLOUDFLARE TUNNEL LIVE!');
      console.log('Use this WebSocket URL in Atlas on your iPad:');
      console.log(`👉  ${wsUrl}`);
      console.log('======================================================\n');
    }
  } catch (err) {
    console.log(`[Tunnel] Notice: Cloudflare tunnel could not be initialized (${err.message}). Local Wi-Fi is active.`);
  }
}

launchTunnel();

// Graceful shutdown
function shutdown() {
  console.log('\nShutting down Atlas Companion Server...');
  killProcessTree(engineProcess);
  freePort(PORT);
  process.exit(0);
}

process.on('SIGINT', shutdown);
process.on('SIGTERM', shutdown);
process.on('exit', () => {
  killProcessTree(engineProcess);
  freePort(PORT);
});
