# Atlas

Atlas is a prototype IDE-style Flutter app with a remote backend engine. It provides a workspace shell for browsing files, editing source files, running commands, and viewing terminal output.

## What it does

- Renders an IDE-like workspace UI with an explorer, editor, terminal, and AI panel shell.
- Connects to a local WebSocket backend to browse the project tree.
- Loads file contents from the backend and lets you edit them in the editor.
- Saves edited files back to disk through the backend.
- Sends shell commands to the backend so the Run button can trigger Flutter commands.

## Running locally

1. Start the backend engine:
   - `cd backend`
   - `npm run ipad`
2. Run the Flutter app:
   - `flutter run`

### Web deployment

When running in a browser, the app connects to the same host that served the page by default. If the backend runs on a different machine or custom host, append `?engineHost=<host>` or `?engineHost=<host>:<port>` to the URL, for example:

- `http://192.168.1.100:8080/?engineHost=192.168.1.100`
- `http://192.168.1.100:8080/?engineHost=192.168.1.100:8080`

### Mobile / native deployment

When running on a phone or tablet against a remote engine, provide the backend host at build time. The backend must be reachable from the device, and your laptop must allow inbound connections to the engine port:

- `flutter run --dart-define=ENGINE_HOST=192.168.1.100`
- `flutter run --dart-define=ENGINE_HOST=192.168.1.100:8080`

If you want to use another backend URL entirely, pass a fully qualified WebSocket URL:

- `--dart-define=ENGINE_HOST=ws://192.168.1.100:8080`

## Validation

- `flutter test`
- `flutter analyze`
