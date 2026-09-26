import 'dart:async';

import '../config.dart';
import '../models/kiosk_settings.dart';
import 'kiosk_backend.dart';
import 'local_database.dart';
import 'pin_verification_service.dart';

/// Caches the single admin-managed `kiosk_settings` row (see
/// supabase/migrations/0007_kiosk_enrollment.sql), refreshed on a
/// self-rescheduling timer driven by the row's own
/// `refresh_interval_seconds` (supabase/migrations/0015_configurable_timings.sql)
/// -- rather than a fixed Timer.periodic -- so an admin's changes
/// (institution name, greeting wording, voice/enrollment toggles, and the
/// interval itself) reach a running kiosk without a restart, and the poll
/// cadence adapts from the next tick after a new interval is fetched.
class KioskSettingsService {
  KioskSettings _settings = KioskSettings.defaults;
  Timer? _nextTick;
  bool _running = false;

  KioskSettings get current => _settings;

  /// Hardware build flag AND the admin's runtime toggle both have to allow
  /// it -- see KioskConfig.enrollmentEnabled's doc comment.
  bool get enrollmentAllowed => KioskConfig.enrollmentEnabled && _settings.enrollmentEnabled;

  Future<void> start() async {
    _running = true;
    await refresh();
    _scheduleNext();
  }

  void _scheduleNext() {
    if (!_running) return;
    _nextTick = Timer(_settings.refreshInterval, () async {
      await refresh();
      _scheduleNext();
    });
  }

  Future<void> refresh() async {
    try {
      _settings = await KioskBackend.instance.fetchKioskSettings();
      // Piggybacks on this poll to keep PinVerificationService's offline
      // fallback current -- never overwrites with null so a transient
      // fetch of a since-cleared PIN doesn't wipe out the last known-good
      // hash (see PinVerificationService's doc comment).
      final hash = _settings.enrollmentPinHash;
      if (hash != null) {
        await LocalDatabase.instance.setSetting(PinVerificationService.pinHashSettingKey, hash);
      }
    } catch (_) {
      // Keep using whatever was last cached (or the defaults); retried on
      // the next tick, same as CameraScreen._refreshEmployees.
    }
  }

  void dispose() {
    _running = false;
    _nextTick?.cancel();
  }
}
