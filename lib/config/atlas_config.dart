import 'package:flutter/foundation.dart';

/// Build-time settings for the companion Atlas engine.
///
/// Supply values with `--dart-define` when running or building the app.
/// When running via `npm run ipad`, the default `ws://localhost:8080` is
/// automatically rewritten to use the browser's host so that iPads on the
/// same LAN can reach the engine without extra flags.
abstract final class AtlasConfig {
  static String get engineUrl {
    String url = const String.fromEnvironment('ATLAS_ENGINE_URL');

    if (url.isEmpty) url = 'ws://localhost:8080';

    // On web, rewrite localhost → the host the page was served from so that
    // remote devices (e.g. iPad on the same Wi-Fi) connect to the right IP.
    if (kIsWeb) {
      final host = Uri.base.host;

      if (host.isNotEmpty &&
          (url.contains('localhost') || url.contains('127.0.0.1'))) {
        url = url
            .replaceAll('localhost', host)
            .replaceAll('127.0.0.1', host);
      }

      // Upgrade to wss:// when the page itself was loaded over HTTPS.
      if (Uri.base.scheme == 'https' && url.startsWith('ws://')) {
        url = url.replaceFirst('ws://', 'wss://');
      }
    }

    debugPrint('Atlas engine URL: $url');
    return url;
  }

  static const engineToken = String.fromEnvironment('ATLAS_ENGINE_TOKEN');
}
