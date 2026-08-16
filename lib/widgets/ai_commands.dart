import 'package:flutter/material.dart';

/// Simple utility class exposing static AI command actions.
/// Currently these are placeholders; they can be expanded to interact
/// with the EngineClient or show UI dialogs.
class AiCommands {
  /// Triggered from the command palette to read a file via the AI.
  static void readFile(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('AI: Read File command invoked')),
    );
  }

  /// Triggered from the command palette to apply an AI‑generated edit.
  static void applyEdit(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('AI: Apply Edit command invoked')),
    );
  }
}
