const { spawn } = require('child_process');
const path = require('path');

const token = process.env.ATLAS_ENGINE_TOKEN || 'atlas-secret-token-12345';
const host = '0.0.0.0';
const port = 8080;

console.log('==================================================');
console.log('Starting Atlas Backend Engine');
console.log(`Host:  ${host}`);
console.log(`Port:  ${port}`);
console.log(`Token: ${token}`);
console.log('==================================================');

const env = {
  ...process.env,
  ATLAS_ENGINE_HOST: host,
  ATLAS_ENGINE_TOKEN: token,
  PORT: String(port),
};

const server = spawn(process.execPath, [path.join(__dirname, '..', 'backend', 'server.js')], {
  env,
  stdio: 'inherit',
});

server.on('exit', (code) => {
  console.log(`Server exited with code ${code}`);
  process.exit(code || 0);
});
