import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// This device's own kiosk login, entered once on DeviceSetupScreen and
/// persisted in the Android Keystore-backed secure storage (not sqflite --
/// these are credentials, not app data) so the same APK can be installed
/// on every tablet and still sign in as a distinct, class-scoped device.
/// See supabase/migrations/0026_kiosk_device_scoping.sql for the server
/// side of what "class-scoped" means.
class DeviceCredentialsStore {
  DeviceCredentialsStore._();
  static final instance = DeviceCredentialsStore._();

  static const _storage = FlutterSecureStorage();
  static const _emailKey = 'device_email';
  static const _passwordKey = 'device_password';

  Future<({String email, String password})?> read() async {
    final email = await _storage.read(key: _emailKey);
    final password = await _storage.read(key: _passwordKey);
    if (email == null || password == null || email.isEmpty || password.isEmpty) {
      return null;
    }
    return (email: email, password: password);
  }

  Future<void> save({required String email, required String password}) async {
    await _storage.write(key: _emailKey, value: email);
    await _storage.write(key: _passwordKey, value: password);
  }

  /// Used by "Re-pair this device" (device_settings_screen.dart) when a
  /// tablet is being reassigned/handed to a different class -- clears the
  /// stored identity so the app falls back to DeviceSetupScreen on next
  /// launch. Does not sign out of Supabase itself; callers do that
  /// separately since this store has no SupabaseClient reference.
  Future<void> clear() async {
    await _storage.delete(key: _emailKey);
    await _storage.delete(key: _passwordKey);
  }
}
