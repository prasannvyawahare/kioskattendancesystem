import 'package:flutter/foundation.dart';

import '../models/enrolled_employee.dart';
import 'attendance_decision_engine.dart';
import 'attendance_mode_service.dart';
import 'ist_clock.dart';
import 'kiosk_backend.dart';
import 'kiosk_settings_service.dart';
import 'local_database.dart';

class AttendanceResult {
  AttendanceResult(this.employee, this.status);
  final EnrolledEmployee employee;

  /// 'check_in' | 'check_out' | 'already_completed'
  final String status;
}

/// Debounces repeat detections of the same person (so standing/lingering in
/// front of the camera doesn't fire multiple attendance calls), then either
/// calls mark_attendance() (online -- the atomic, authoritative decision in
/// Postgres, see supabase/migrations/0015_configurable_timings.sql) or
/// falls back to AttendanceDecisionEngine (offline -- the same decision
/// made locally, queued for SyncService to push later). The cooldown is
/// read from settingsService.current.minScanGap on every call (admin-
/// configurable, matches that function's minimum check-in/check-out gap)
/// so a person who stays in frame isn't re-scanned and checked out moments
/// after checking in; the DB-side gap (or the local engine's, offline) is
/// still the authoritative guard (e.g. if the kiosk app restarts and this
/// in-memory map is lost).
class AttendanceService {
  AttendanceService({
    required this.attendanceModeService,
    required this.settingsService,
  }) : _decisionEngine = AttendanceDecisionEngine();

  final AttendanceModeService attendanceModeService;
  final KioskSettingsService settingsService;
  final AttendanceDecisionEngine _decisionEngine;
  final Map<String, DateTime> _lastScanAt = {};

  Future<AttendanceResult?> handleMatch(EnrolledEmployee employee, double similarity) async {
    final settings = settingsService.current;
    final cooldown = settings.minScanGap;
    final onlineTimeout = settings.onlineTimeout;

    final now = DateTime.now();
    final last = _lastScanAt[employee.id];
    if (last != null && now.difference(last) < cooldown) {
      return null;
    }
    _lastScanAt[employee.id] = now;

    final mode = attendanceModeService.mode.value;

    try {
      final status = await KioskBackend.instance
          .markAttendance(employee.id, confidence: similarity, mode: mode.toDbValue())
          .timeout(onlineTimeout);
      await _reconcileLocalState(employee.id, status);
      return AttendanceResult(employee, status);
    } catch (e) {
      // No network (or the server call timed out/failed) -- decide locally
      // and queue the event for SyncService to push once connectivity is
      // back. Same decision engine backs both branches of this function.
      debugPrint('markAttendance failed online ($e), falling back to offline decision engine');
      final decision =
          await _decisionEngine.decide(employeeId: employee.id, mode: mode, minGap: cooldown);
      debugPrint('offline decision for ${employee.id}: ${decision.status}');
      if (decision.status != 'already_completed') {
        await LocalDatabase.instance.enqueueAttendanceEvent(
          employeeId: employee.id,
          eventDate: decision.eventDate,
          eventType: decision.status,
          scannedAt: IstClock.nowUtc().toIso8601String(),
          confidence: similarity,
        );
      }
      return AttendanceResult(employee, decision.status);
    }
  }

  Future<void> _reconcileLocalState(String employeeId, String status) async {
    final today = IstClock.todayKey();
    switch (status) {
      case 'check_in':
        await LocalDatabase.instance.upsertAttendanceState(
          employeeId: employeeId,
          eventDate: today,
          checkInAt: IstClock.nowUtc().toIso8601String(),
        );
        break;
      case 'check_out':
        await LocalDatabase.instance.upsertAttendanceState(
          employeeId: employeeId,
          eventDate: today,
          hasCheckOut: true,
        );
        break;
      default:
        // already_completed -- local state (if any) is already accurate.
        break;
    }
  }
}
