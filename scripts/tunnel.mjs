import { startTunnel } from 'untun';

async function main() {
  console.log('Starting Cloudflare tunnel for port 8080...');
  const tunnel = await startTunnel({
    port: 8080,
    hostname: '127.0.0.1',
    protocol: 'http',
  });
  
  if (!tunnel) {
    console.error('Failed to start tunnel');
    process.exit(1);
  }
  
  const url = await tunnel.getURL();
  const wsUrl = url.replace(/^http/, 'ws');
  console.log('----------------------------------------------------');
  console.log('TUNNEL READY!');
  console.log('HTTP URL: ' + url);
  console.log('USE THIS IN ATLAS ON YOUR IPAD:');
  console.log(wsUrl);
  console.log('----------------------------------------------------');
}

main().catch(err => {
  console.error('Tunnel error:', err);
  process.exit(1);
});
