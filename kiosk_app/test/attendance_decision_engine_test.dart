import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:kiosk_app/models/attendance_mode.dart';
import 'package:kiosk_app/services/attendance_decision_engine.dart';
import 'package:kiosk_app/services/local_database.dart';

/// Exercises AttendanceDecisionEngine against a real (ffi-backed) sqlite
/// LocalDatabase, mirroring mark_attendance()'s branches in
/// supabase/migrations/0013_offline_sync.sql / 0017_hardening.sql one for
/// one. This is the Dart-side half of that SQL function's decision logic --
/// nothing currently catches the two drifting apart except this file, so
/// keep both updated together.
void main() {
  final engine = AttendanceDecisionEngine();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    await LocalDatabase.instance.open();
    // Wipes every attendance_state row so each test starts from a clean
    // slate regardless of what a previous test run left on disk --
    // pruneAttendanceStateBefore is the only delete-all LocalDatabase
    // already exposes, so reuse it with a date past any real event_date.
    await LocalDatabase.instance.pruneAttendanceStateBefore('9999-12-31');
  });

  group('both mode', () {
    test('first scan of the day checks in', () async {
      final result = await engine.decide(
        employeeId: 'emp-both-1',
        mode: AttendanceMode.both,
        minGap: const Duration(minutes: 10),
      );
      expect(result.status, 'check_in');
    });

    test('second scan within the min gap re-reports check_in, not check_out', () async {
      const id = 'emp-both-2';
      await engine.decide(employeeId: id, mode: AttendanceMode.both, minGap: const Duration(days: 1));
      final result = await engine.decide(
        employeeId: id,
        mode: AttendanceMode.both,
        minGap: const Duration(days: 1),
      );
      expect(result.status, 'check_in');
    });

    test('second scan after the min gap checks out', () async {
      const id = 'emp-both-3';
      await engine.decide(employeeId: id, mode: AttendanceMode.both, minGap: Duration.zero);
      final result =
          await engine.decide(employeeId: id, mode: AttendanceMode.both, minGap: Duration.zero);
      expect(result.status, 'check_out');
    });

    test('third scan is already_completed', () async {
      const id = 'emp-both-4';
      await engine.decide(employeeId: id, mode: AttendanceMode.both, minGap: Duration.zero);
      await engine.decide(employeeId: id, mode: AttendanceMode.both, minGap: Duration.zero);
      final result =
          await engine.decide(employeeId: id, mode: AttendanceMode.both, minGap: Duration.zero);
      expect(result.status, 'already_completed');
    });
  });

  group('check_in_only mode', () {
    test('every scan after the first is already_completed', () async {
      const id = 'emp-cio-1';
      final first = await engine.decide(
        employeeId: id,
        mode: AttendanceMode.checkInOnly,
        minGap: const Duration(minutes: 10),
      );
      final second = await engine.decide(
        employeeId: id,
        mode: AttendanceMode.checkInOnly,
        minGap: const Duration(minutes: 10),
      );
      expect(first.status, 'check_in');
      expect(second.status, 'already_completed');
    });
  });

  group('check_out_only mode', () {
    test('does not require a prior check-in', () async {
      const id = 'emp-coo-1';
      final first = await engine.decide(
        employeeId: id,
        mode: AttendanceMode.checkOutOnly,
        minGap: const Duration(minutes: 10),
      );
      final second = await engine.decide(
        employeeId: id,
        mode: AttendanceMode.checkOutOnly,
        minGap: const Duration(minutes: 10),
      );
      expect(first.status, 'check_out');
      expect(second.status, 'already_completed');
    });
  });
}
