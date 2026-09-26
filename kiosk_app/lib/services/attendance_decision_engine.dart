import '../models/attendance_mode.dart';
import 'ist_clock.dart';
import 'local_database.dart';

/// 'check_in' | 'check_out' | 'already_completed' -- same vocabulary
/// mark_attendance() returns, so callers don't need to branch differently
/// depending on whether the decision came from the server or from here.
class AttendanceDecision {
  AttendanceDecision(this.status, this.eventDate);
  final String status;

  /// yyyy-MM-dd this decision was filed under (IstClock.todayKey() at
  /// decide()-time) -- callers need this to key attendance_state/
  /// attendance_queue writes consistently with what was actually decided.
  final String eventDate;
}

/// Dart mirror of mark_attendance() in
/// supabase/migrations/0015_configurable_timings.sql, run against the
/// local attendance_state cache instead of Postgres. Used for offline
/// scans, and must stay behaviorally identical to the SQL function --
/// change both sides together.
class AttendanceDecisionEngine {
  /// [minGap] is taken per-call rather than fixed at construction because
  /// it's admin-configurable (KioskSettings.minScanGap) and can change
  /// mid-session -- callers should pass the current value from
  /// KioskSettingsService, not cache it.
  Future<AttendanceDecision> decide({
    required String employeeId,
    required AttendanceMode mode,
    required Duration minGap,
  }) async {
    final today = IstClock.todayKey();
    final state = await LocalDatabase.instance.getAttendanceState(employeeId, today);
    final checkInAtRaw = state?['check_in_at'] as String?;
    final hasCheckIn = checkInAtRaw != null;
    final hasCheckOut = ((state?['has_check_out'] as int?) ?? 0) == 1;

    switch (mode) {
      case AttendanceMode.checkInOnly:
        if (hasCheckIn) return AttendanceDecision('already_completed', today);
        await LocalDatabase.instance.upsertAttendanceState(
          employeeId: employeeId,
          eventDate: today,
          checkInAt: IstClock.nowUtc().toIso8601String(),
        );
        return AttendanceDecision('check_in', today);

      case AttendanceMode.checkOutOnly:
        // Deliberately doesn't require a prior check-in row: a
        // check-out-only kiosk is presumably the only touchpoint that day.
        if (hasCheckOut) return AttendanceDecision('already_completed', today);
        await LocalDatabase.instance.upsertAttendanceState(
          employeeId: employeeId,
          eventDate: today,
          hasCheckOut: true,
        );
        return AttendanceDecision('check_out', today);

      case AttendanceMode.both:
        if (!hasCheckIn) {
          await LocalDatabase.instance.upsertAttendanceState(
            employeeId: employeeId,
            eventDate: today,
            checkInAt: IstClock.nowUtc().toIso8601String(),
          );
          return AttendanceDecision('check_in', today);
        }

        if (hasCheckOut) {
          return AttendanceDecision('already_completed', today);
        }

        final checkInAt = DateTime.parse(checkInAtRaw);
        if (IstClock.nowUtc().difference(checkInAt) < minGap) {
          // Still within the minimum gap since check-in: treat as a
          // duplicate check-in scan rather than checking the person out,
          // same as the SQL function.
          return AttendanceDecision('check_in', today);
        }

        await LocalDatabase.instance.upsertAttendanceState(
          employeeId: employeeId,
          eventDate: today,
          hasCheckOut: true,
        );
        return AttendanceDecision('check_out', today);
    }
  }
}
