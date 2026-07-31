# Atlas

Atlas is a Flutter workspace client with a companion Node.js engine that runs
on your development computer.

## Run Atlas locally

1. Start the engine from the project root. Choose a long, private token:

   ```powershell
   $env:ATLAS_ENGINE_TOKEN = 'replace-with-a-long-random-token'
   npm --prefix backend start
   ```

2. Run the Flutter application with the same token:

   ```powershell
   flutter run --dart-define=ATLAS_ENGINE_TOKEN=replace-with-a-long-random-token
   ```

## Run on an iPad over your local network

The iPad must be on the same trusted Wi-Fi network as the computer running the
engine. Find the computer's LAN IP address, then start the engine as above and
build/run Flutter with that address and the same token:

```text
--dart-define=ATLAS_ENGINE_URL=ws://192.168.1.50:8080
--dart-define=ATLAS_ENGINE_TOKEN=replace-with-a-long-random-token
```

Never expose port 8080 to the public internet. The engine can read project
files, save edits, and run commands, so it is intended only for a private local
network.

Open a file in the Explorer, edit it in the central editor, then use the
**Save** action in the editor status bar. Atlas currently writes only existing
files inside this project; it cannot create files or save outside the workspace.

Use the Explorer header's **New File** and **New Folder** controls to create
entries. Enter a relative workspace path such as `lib/widgets/sidebar.dart`.
Atlas will never overwrite an existing entry and requires the parent folder to
already exist.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
