/// Build-time configuration, injected via --dart-define so nothing
/// sensitive lives in source control. See kiosk_app/README.md for the full
/// `flutter run` / `flutter build` invocation.
class KioskConfig {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  static const kioskEmail = String.fromEnvironment('KIOSK_EMAIL');
  static const kioskPassword = String.fromEnvironment('KIOSK_PASSWORD');

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
