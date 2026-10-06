/// Build-time configuration, injected via --dart-define so nothing
/// sensitive lives in source control. See kiosk_app/README.md for the full
/// `flutter run` / `flutter build` invocation.
class KioskConfig {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  /// Optional, dev-convenience-only fallback: a single APK built with these
  /// signs in as that one shared kiosk account without ever showing
  /// DeviceSetupScreen, matching the old (pre-device-pairing) behavior. The
  /// normal path for a real deployment is now pairing each tablet at
  /// runtime (DeviceSetupScreen -> DeviceCredentialsStore) with per-class
  /// credentials created from the admin panel's Devices page, since that's
  /// what lets one APK be installed on every tablet. See
  /// SupabaseBackend.signInAsKiosk for how the two are reconciled.
  static const kioskEmail = String.fromEnvironment('KIOSK_EMAIL');
  static const kioskPassword = String.fromEnvironment('KIOSK_PASSWORD');

  /// Hardware-level enrollment gate: only kiosks built/installed with
  /// `--dart-define=ENABLE_ENROLLMENT=true` compile the PIN-entry gesture
  /// and member-management screens in at all. Combined at runtime with
  /// `kiosk_settings.enrollment_enabled` (KioskSettingsService) so an admin
  /// can also disable enrollment fleet-wide without reinstalling anything.
  static const enrollmentEnabled = bool.fromEnvironment('ENABLE_ENROLLMENT');

  static void assertConfigured() {
    assert(
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty,
      'Missing --dart-define values. See kiosk_app/README.md.',
    );
  }
}
