/// Build-time configuration, injected via --dart-define so nothing
/// sensitive lives in source control. See kiosk_app/README.md for the full
/// `flutter run` / `flutter build` invocation.
class KioskConfig {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
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
      supabaseUrl.isNotEmpty &&
          supabaseAnonKey.isNotEmpty &&
          kioskEmail.isNotEmpty &&
          kioskPassword.isNotEmpty,
      'Missing --dart-define values. See kiosk_app/README.md.',
    );
  }
}
