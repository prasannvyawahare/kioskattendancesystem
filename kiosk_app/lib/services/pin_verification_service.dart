import 'package:bcrypt/bcrypt.dart';
import 'package:flutter/foundation.dart';

import 'kiosk_backend.dart';
import 'kiosk_settings_service.dart';
import 'local_database.dart';

/// Thrown when the PIN can't be checked at all -- offline, and no PIN hash
/// has ever been cached locally (e.g. first run, never yet been online
/// long enough for KioskSettingsService's poll to land). Distinct from a
/// definitively wrong PIN (that's just `false`), since the caller should
/// tell the operator to connect once rather than "wrong PIN, try again".
class PinVerificationUnavailable implements Exception {}

/// Thrown by the offline fallback when too many wrong PINs have been
/// entered recently -- mirrors _check_enrollment_pin()'s server-side
/// lockout (5 failed attempts -> 5 minute lockout) so an offline PIN pad
/// can't be brute-forced at UI-tap speed just because the server-side
/// bookkeeping is unreachable.
class PinVerificationLocked implements Exception {
  PinVerificationLocked(this.lockedUntil);
  final DateTime lockedUntil;
}

/// Same online/offline split as AttendanceService: tries the server RPC
/// first (the authoritative check, with real lockout tracking), and on any
/// failure falls back to a local bcrypt comparison against the PIN hash
/// KioskSettingsService caches on every successful settings poll (see its
/// doc comment -- that hash is already sent to the kiosk in every
/// kiosk_settings row under RLS, this just finally uses it). Offline
/// attempts are locally rate-limited (see PinVerificationLocked) --
/// bcrypt's own cost factor already slows brute-forcing somewhat, but nothing
/// previously stopped rapid UI-tap-speed retries while offline.
class PinVerificationService {
  PinVerificationService({required this.settingsService});

  final KioskSettingsService settingsService;

  static const pinHashSettingKey = 'enrollment_pin_hash';
  static const _failedAttemptsKey = 'offline_pin_failed_attempts';
  static const _lockedUntilKey = 'offline_pin_locked_until';
  static const _maxAttempts = 5;
  static const _lockoutDuration = Duration(minutes: 5);

  Future<bool> verify(String pin) async {
    try {
      return await KioskBackend.instance
          .verifyEnrollmentPin(pin)
          .timeout(settingsService.current.onlineTimeout);
    } catch (e) {
      debugPrint('verifyEnrollmentPin failed online ($e), trying cached PIN hash');
      final hash = await LocalDatabase.instance.getSetting(pinHashSettingKey);
      if (hash == null) {
        debugPrint('no PIN hash cached yet -- must be online at least once first');
        throw PinVerificationUnavailable();
      }
      return _verifyOffline(pin, hash);
    }
  }

  Future<bool> _verifyOffline(String pin, String hash) async {
    final lockedUntilRaw = await LocalDatabase.instance.getSetting(_lockedUntilKey);
    final lockedUntil = lockedUntilRaw == null ? null : DateTime.tryParse(lockedUntilRaw);
    if (lockedUntil != null && lockedUntil.isAfter(DateTime.now())) {
      throw PinVerificationLocked(lockedUntil);
    }

    final ok = BCrypt.checkpw(pin, hash);
    if (ok) {
      await LocalDatabase.instance.setSetting(_failedAttemptsKey, '0');
    } else {
      final attemptsRaw = await LocalDatabase.instance.getSetting(_failedAttemptsKey);
      final attempts = (int.tryParse(attemptsRaw ?? '0') ?? 0) + 1;
      await LocalDatabase.instance.setSetting(_failedAttemptsKey, attempts.toString());
      if (attempts >= _maxAttempts) {
        await LocalDatabase.instance.setSetting(
          _lockedUntilKey,
          DateTime.now().add(_lockoutDuration).toIso8601String(),
        );
      }
    }
    return ok;
  }
}
