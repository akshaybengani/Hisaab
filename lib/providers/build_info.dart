/// Build identity, shown on the settings screen.
///
/// Held as a constant rather than read back through a plugin: this app is
/// sideloaded from one machine, and a plugin would be a dependency bought for
/// one line of text. Keep it in step with `version:` in `pubspec.yaml`.
abstract final class BuildInfo {
  static const String version = '1.0.0';
  static const String buildNumber = '1';

  /// "1.0.0 (1)".
  static String get label => '$version ($buildNumber)';
}
