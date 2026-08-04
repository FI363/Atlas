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

## AI Panel Integration

This project is configured to work with the built-in AI agent in your IDE (e.g., VS Code's AI sidebar). To enable full code-aware AI assistance:

1. Open the project folder in VS Code
2. Ensure the AI extension is installed and enabled
3. The `.vscode/settings.json` configures the project root as the AI source context
4. Use prompts like:
   - "What does this function do?"
   - "Add a new button to the Flutter UI"
   - "Explain the build.gradle configuration"

The AI panel can browse and suggest changes to Dart/Flutter code, access dependencies (`pubspec.yaml`), and modify platform-specific code.

The engine can read/write project files and execute shell commands. **Never expose ports 8080/8081 to the public internet.** This is designed for trusted local networks only. Authentication uses a shared token passed via `--dart-define`.

## Atlas AI and workspace persistence

Use **Settings → AI Agent** to choose the provider, model, endpoint, and credentials. Atlas uses OpenRouter's OpenAI-compatible `/api/v1` API; it does not require Claude Code or Anthropic environment variables. The AI panel accepts text/files/images and clipboard image paste (`Ctrl+V` on Windows).

Atlas remembers the selected workspace folder and user settings in the per-user `~/.atlas` state directory. Opening another folder changes the remembered workspace; restarting Atlas does not reset it.
