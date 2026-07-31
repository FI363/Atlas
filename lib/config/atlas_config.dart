/// Build-time settings for the companion Atlas engine.
///
/// Supply values with `--dart-define` when running or building the app. The
/// default endpoint supports local desktop development; an iPad build must use
/// the computer's LAN address instead of `localhost`.
abstract final class AtlasConfig {
  static const engineUrl = String.fromEnvironment(
    'ATLAS_ENGINE_URL',
    defaultValue: 'ws://localhost:8080',
  );

  static const engineToken = String.fromEnvironment('ATLAS_ENGINE_TOKEN');
}
