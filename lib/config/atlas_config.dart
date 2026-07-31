import 'package:flutter/foundation.dart';

/// Build-time settings for the companion Atlas engine.
///
/// Supply values with `--dart-define` when running or building the app. The
/// default endpoint supports local desktop development; an iPad build must use
/// the computer's LAN address instead of `localhost`.
abstract final class AtlasConfig {
  static String get engineUrl {
    String url = const String.fromEnvironment('ATLAS_ENGINE_URL');
    
    // If not provided, fallback to a sensible default
    if (url.isEmpty) {
      url = 'ws://localhost:8080';
    }

    // If we're on the web and the URL points to localhost, we aggressively 
    // rewrite it to use the browser's current host to ensure devices like 
    // iPads can connect to the dev server on the local network.
    if (kIsWeb) {
      final host = Uri.base.host;
      if (host.isNotEmpty && (url.contains('localhost') || url.contains('127.0.0.1'))) {
        url = url.replaceAll('localhost', host).replaceAll('127.0.0.1', host);
      }
      if (Uri.base.scheme == 'https' && url.startsWith('ws://')) {
        url = url.replaceFirst('ws://', 'wss://');
      }
    }
    
    return url;
  }

  static const engineToken = String.fromEnvironment('ATLAS_ENGINE_TOKEN');
}
