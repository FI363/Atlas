# Atlas

A Flutter-based code editor / IDE that runs in the browser (targeting iPad Safari) with a companion Node.js "engine" on your development machine providing file-system access and shell execution over WebSockets.

## Prerequisites

- **Node.js** ≥ 18
- **Flutter SDK** ≥ 3.9
- Both devices on the **same Wi-Fi network** (for iPad mode)

## Quick Start (desktop browser)

```powershell
npm install
npm run dev
```

This starts the engine on port `8080` and opens the Flutter app in Chrome.

## Run on iPad over LAN

### 1. Find your laptop's LAN IP

```powershell
ipconfig
```

Look for the **IPv4 Address** under your Wi-Fi adapter (e.g. `192.168.1.50`).

### 2. Open Windows Firewall for ports 8080 and 8081

```powershell
# Run PowerShell as Administrator
netsh advfirewall firewall add rule name="Atlas Engine WS" dir=in action=allow protocol=TCP localport=8080
netsh advfirewall firewall add rule name="Atlas Flutter Web" dir=in action=allow protocol=TCP localport=8081
```

### 3. Start Atlas in iPad mode

```powershell
npm run ipad
```

This starts:
- The WebSocket engine on `0.0.0.0:8080` (all interfaces)
- The Flutter web server on `0.0.0.0:8081`

### 4. Open on iPad

In Safari, navigate to:

```
http://<YOUR_LAN_IP>:8081
```

The app automatically rewrites `ws://localhost:8080` → `ws://<YOUR_LAN_IP>:8080` so the iPad connects to the engine without extra flags.

## Available npm scripts

| Script | Description |
|--------|-------------|
| `npm run dev` | Engine + Chrome (local development) |
| `npm run ipad` | Engine + web-server on `0.0.0.0` (LAN access) |
| `npm run engine` | Engine only (port 8080) |

## Architecture

```
iPad (Safari)                    Laptop
┌─────────────────┐   WebSocket   ┌──────────────────┐
│  Flutter Web UI  │ ◄──────────► │  Node.js Engine   │
│  (port 8081)     │   :8080      │  (server.js)      │
│                  │              │  • File I/O       │
│  • Editor        │              │  • Shell commands  │
│  • File Explorer │              │  • Auth (token)    │
│  • Terminal      │              └──────────────────┘
│  • AI Panel      │
└─────────────────┘
```

## Security

The engine can read/write project files and execute shell commands. **Never expose ports 8080/8081 to the public internet.** This is designed for trusted local networks only. Authentication uses a shared token passed via `--dart-define`.
