import 'package:flutter/foundation.dart';

import '../models/attendance_mode.dart';
import 'local_database.dart';

const _settingKey = 'attendance_mode';

/// Device-local attendance-mode setting (Both / Check-in only / Check-out
/// only), read on every scan and editable from DeviceSettingsScreen. Backed
/// by LocalDatabase.local_settings rather than the shared kiosk_settings
/// Postgres row -- this is per-kiosk, not admin-managed (see
/// AttendanceMode's doc comment).
class AttendanceModeService {
  final ValueNotifier<AttendanceMode> mode = ValueNotifier(AttendanceMode.both);

  /// Loads the persisted mode, if any, before the notifier is first read.
  /// Call once at startup, before wiring anything else to `mode`.
  Future<void> load() async {
    final stored = await LocalDatabase.instance.getSetting(_settingKey);
    mode.value = AttendanceMode.fromDbValue(stored);
  }

  Future<void> setMode(AttendanceMode newMode) async {
    mode.value = newMode;
    await LocalDatabase.instance.setSetting(_settingKey, newMode.toDbValue());
  }
}
