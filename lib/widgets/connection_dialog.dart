import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../state/workspace_state.dart';

/// Modal dialog for pairing and connecting the Atlas iPad/desktop app to the companion Node.js engine.
class ConnectionDialog extends StatefulWidget {
  const ConnectionDialog({super.key, required this.workspaceState});

  final WorkspaceState workspaceState;

  static Future<void> show(BuildContext context, WorkspaceState workspaceState) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (context) => ConnectionDialog(workspaceState: workspaceState),
    );
  }

  @override
  State<ConnectionDialog> createState() => _ConnectionDialogState();
}

class _ConnectionDialogState extends State<ConnectionDialog> {
  late final TextEditingController _urlController;
  late final TextEditingController _tokenController;
  bool _obscureToken = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController(text: widget.workspaceState.settings.engineUrl);
    _tokenController = TextEditingController(text: widget.workspaceState.settings.engineToken);
  }

  @override
  void dispose() {
    _urlController.dispose();
    _tokenController.dispose();
    super.dispose();
  }

  String _normalizeUrl(String raw) {
    var trimmed = raw.trim();
    if (trimmed.isEmpty) return 'ws://localhost:8080';
    if (!trimmed.startsWith('ws://') && !trimmed.startsWith('wss://')) {
      if (trimmed.startsWith('http://')) {
        trimmed = trimmed.replaceFirst('http://', 'ws://');
      } else if (trimmed.startsWith('https://')) {
        trimmed = trimmed.replaceFirst('https://', 'wss://');
      } else {
        trimmed = 'ws://$trimmed';
      }
    }
    // If no port specified and doesn't contain colon after scheme
    final afterScheme = trimmed.replaceFirst(RegExp(r'^wss?://'), '');
    if (!afterScheme.contains(':') && !afterScheme.contains('/')) {
      trimmed = '$trimmed:8080';
    }
    return trimmed;
  }

  Future<void> _handleConnect() async {
    setState(() => _isSaving = true);
    final normalizedUrl = _normalizeUrl(_urlController.text);
    final token = _tokenController.text.trim();

    await widget.workspaceState.updateConnectionSettings(normalizedUrl, token);
    
    if (mounted) {
      setState(() => _isSaving = false);
      Navigator.of(context).pop();
    }
  }

  Future<void> _pasteToken() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null && mounted) {
      setState(() {
        _tokenController.text = data!.text!.trim();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isConnected = widget.workspaceState.engine.isConnected;
    final recentUrls = widget.workspaceState.settings.recentEngineUrls;

    return Dialog(
      backgroundColor: const Color(0xFF1E1E1E),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFF3C3C3C)),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Container(
        width: 520,
        padding: const EdgeInsets.all(24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF264F78).withAlpha(100),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.wifi_tethering_rounded, color: Color(0xFF3794FF), size: 22),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Atlas Engine Connection',
                          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: Colors.white),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Connect native iPad to your laptop development engine',
                          style: TextStyle(fontSize: 12, color: Color(0xFF8C8C8C)),
                        ),
                      ],
                    ),
                  ),
                  // Live Connection Status
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: isConnected ? const Color(0xFF1B3D2F) : const Color(0xFF3D261B),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isConnected ? const Color(0xFF4EC9B0) : const Color(0xFFCE9178),
                        width: 0.8,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isConnected ? const Color(0xFF4EC9B0) : const Color(0xFFCE9178),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          isConnected ? 'Connected' : 'Disconnected',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: isConnected ? const Color(0xFF4EC9B0) : const Color(0xFFCE9178),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const Divider(color: Color(0xFF2D2D2D), height: 1),
              const SizedBox(height: 20),

              // Host URL input
              const Text(
                'Engine WebSocket URL or IP Address',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Color(0xFFD4D4D4)),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _urlController,
                style: const TextStyle(fontSize: 13, color: Colors.white, fontFamily: 'monospace'),
                decoration: InputDecoration(
                  hintText: 'e.g. ws://192.168.1.50:8080 or 100.x.y.z:8080',
                  hintStyle: const TextStyle(fontSize: 12, color: Color(0xFF6C6C6C)),
                  prefixIcon: const Icon(Icons.lan_outlined, size: 18, color: Color(0xFF8C8C8C)),
                  filled: true,
                  fillColor: const Color(0xFF252526),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: const BorderSide(color: Color(0xFF3C3C3C)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: const BorderSide(color: Color(0xFF3C3C3C)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: const BorderSide(color: Color(0xFF0E639C)),
                  ),
                ),
              ),

              // Recent Hosts chips
              if (recentUrls.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: recentUrls.map((url) {
                    return InkWell(
                      onTap: () => setState(() => _urlController.text = url),
                      borderRadius: BorderRadius.circular(4),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFF2A2D2E),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: const Color(0xFF3E3E42)),
                        ),
                        child: Text(
                          url,
                          style: const TextStyle(fontSize: 11, color: Color(0xFF9CDCFE), fontFamily: 'monospace'),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],

              const SizedBox(height: 18),

              // Engine Token Input
              const Text(
                'Engine Auth Token',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Color(0xFFD4D4D4)),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _tokenController,
                obscureText: _obscureToken,
                style: const TextStyle(fontSize: 13, color: Colors.white, fontFamily: 'monospace'),
                decoration: InputDecoration(
                  hintText: 'Paste session token from terminal',
                  hintStyle: const TextStyle(fontSize: 12, color: Color(0xFF6C6C6C)),
                  prefixIcon: const Icon(Icons.key_outlined, size: 18, color: Color(0xFF8C8C8C)),
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: _obscureToken ? 'Show Token' : 'Hide Token',
                        icon: Icon(
                          _obscureToken ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                          size: 18,
                          color: const Color(0xFF8C8C8C),
                        ),
                        onPressed: () => setState(() => _obscureToken = !_obscureToken),
                      ),
                      IconButton(
                        tooltip: 'Paste from Clipboard',
                        icon: const Icon(Icons.paste_rounded, size: 18, color: Color(0xFF3794FF)),
                        onPressed: _pasteToken,
                      ),
                      const SizedBox(width: 4),
                    ],
                  ),
                  filled: true,
                  fillColor: const Color(0xFF252526),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: const BorderSide(color: Color(0xFF3C3C3C)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: const BorderSide(color: Color(0xFF3C3C3C)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: const BorderSide(color: Color(0xFF0E639C)),
                  ),
                ),
              ),

              const SizedBox(height: 18),

              // Quick Help Info Box
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF252526),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFF2D2D2D)),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline, size: 16, color: Color(0xFF3794FF)),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'On your laptop, start Atlas in LAN mode using:\n'
                        'npm run ipad\n'
                        'The terminal will output your Wi-Fi LAN IP (e.g. ws://192.168.x.x:8080) and session token.',
                        style: TextStyle(fontSize: 11, height: 1.4, color: Color(0xFFCCCCCC)),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFFCCCCCC),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: _isSaving ? null : _handleConnect,
                    icon: _isSaving
                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.check_circle_outline_rounded, size: 16),
                    label: Text(_isSaving ? 'Connecting...' : 'Connect & Save'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0E639C),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
