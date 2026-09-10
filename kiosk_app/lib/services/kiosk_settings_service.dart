import 'dart:async';

import '../config.dart';
import '../models/kiosk_settings.dart';
import 'supabase_service.dart';

/// Caches the single admin-managed `kiosk_settings` row (see
/// supabase/migrations/0007_kiosk_enrollment.sql), refreshed on the same
/// periodic-timer pattern CameraScreen already uses for employees, so an
/// admin's changes (institution name, greeting wording, voice/enrollment
/// toggles) reach a running kiosk without a restart.
class KioskSettingsService {
  KioskSettingsService({this.pollInterval = const Duration(seconds: 60)});

  final Duration pollInterval;

  KioskSettings _settings = KioskSettings.defaults;
  Timer? _timer;

  KioskSettings get current => _settings;

  /// Hardware build flag AND the admin's runtime toggle both have to allow
  /// it -- see KioskConfig.enrollmentEnabled's doc comment.
  bool get enrollmentAllowed => KioskConfig.enrollmentEnabled && _settings.enrollmentEnabled;

  Future<void> start() async {
    await refresh();
    _timer = Timer.periodic(pollInterval, (_) => refresh());
  }

  Future<void> refresh() async {
    try {
      _settings = await SupabaseService.instance.fetchKioskSettings();
    } catch (_) {
      // Keep using whatever was last cached (or the defaults); retried on
      // the next tick, same as CameraScreen._refreshEmployees.
    }
  }

  void dispose() => _timer?.cancel();
}
