import 'package:flutter/foundation.dart';

import 'error_logger.dart';
import 'face_matcher.dart';
import 'ist_clock.dart';
import 'local_database.dart';
import 'kiosk_backend.dart';

class SyncStatus {
  const SyncStatus({required this.isSyncing, this.lastSyncedAt, this.pendingCount = 0});

  final bool isSyncing;
  final DateTime? lastSyncedAt;
  final int pendingCount;

  SyncStatus copyWith({bool? isSyncing, DateTime? lastSyncedAt, int? pendingCount}) {
    return SyncStatus(
      isSyncing: isSyncing ?? this.isSyncing,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
      pendingCount: pendingCount ?? this.pendingCount,
    );
  }
}

enum SyncOutcome { ok, alreadyInProgress, failed }

class SyncResult {
  const SyncResult(this.outcome, [this.error]);
  final SyncOutcome outcome;
  final Object? error;
}

const _lastSyncedKey = 'last_synced_at';

/// Owns every bit of network+local-cache interplay for the offline path:
/// pushing the queued attendance_queue events, refreshing the cached
/// roster, and reconciling today's attendance_state. The manual "Sync now"
/// button, the ~8h background timer, and the connectivity-regained
/// listener in CameraScreen all funnel into syncNow() -- the in-flight
/// guard below is what keeps those three triggers from racing each other.
class SyncService {
  SyncService({required FaceMatcher matcher}) : _matcher = matcher;

  final FaceMatcher _matcher;
  final ValueNotifier<SyncStatus> status = ValueNotifier(const SyncStatus(isSyncing: false));

  bool _syncing = false;

  Future<void> loadInitialStatus() async {
    final pending = await LocalDatabase.instance.pendingAttendanceCount();
    final lastSyncedRaw = await LocalDatabase.instance.getSetting(_lastSyncedKey);
    status.value = SyncStatus(
      isSyncing: false,
      pendingCount: pending,
      lastSyncedAt: lastSyncedRaw == null ? null : DateTime.tryParse(lastSyncedRaw),
    );
  }

  /// Network fetch of the enrolled roster, written through to
  /// LocalDatabase and pushed into the live matcher. Falls back to the
  /// on-disk cache only when the matcher is currently empty (first boot
  /// while offline) -- otherwise keeps whatever's already loaded rather
  /// than churning the matcher on every failed poll, same as the previous
  /// in-memory-only behavior.
  Future<void> refreshEmployeesOnly() async {
    try {
      final employees = await KioskBackend.instance.fetchEnrolledEmployees();
      _matcher.updateEmployees(employees);
      await LocalDatabase.instance.replaceCachedEmployees(employees);
      debugPrint('refreshEmployeesOnly: fetched ${employees.length} employees from backend');
    } catch (e) {
      debugPrint('refreshEmployeesOnly: online fetch failed ($e), '
          'matcher currently has ${_matcher.hasEmployees ? "some" : "no"} employees in memory');
      if (!_matcher.hasEmployees) {
        final cached = await LocalDatabase.instance.loadCachedEmployees();
        debugPrint('refreshEmployeesOnly: loaded ${cached.length} employees from local cache');
        if (cached.isNotEmpty) _matcher.updateEmployees(cached);
      }
    }

    // Independent try/catch: a members-list hiccup shouldn't trip the
    // employee-matching fallback logic above, and vice versa -- these are
    // two unrelated caches (all active members here vs. only
    // fully-recognizable ones above) piggybacking on the same poll cycle.
    try {
      final members = await KioskBackend.instance.fetchAllMembers();
      await LocalDatabase.instance.replaceCachedMembers(members);
    } catch (_) {
      // Keep whatever's cached; MemberListScreen falls back to it directly.
    }
  }

  Future<SyncResult> syncNow({bool manual = false}) async {
    if (_syncing) return const SyncResult(SyncOutcome.alreadyInProgress);
    _syncing = true;
    status.value = status.value.copyWith(isSyncing: true);

    try {
      await _ensureSession();
      await _drainQueue();
      await refreshEmployeesOnly();
      await _reconcileToday();
      await _pruneOldAttendanceState();

      final now = DateTime.now();
      await LocalDatabase.instance.setSetting(_lastSyncedKey, now.toIso8601String());
      status.value = SyncStatus(
        isSyncing: false,
        lastSyncedAt: now,
        pendingCount: await LocalDatabase.instance.pendingAttendanceCount(),
      );
      return const SyncResult(SyncOutcome.ok);
    } catch (e) {
      status.value = status.value.copyWith(
        isSyncing: false,
        pendingCount: await LocalDatabase.instance.pendingAttendanceCount(),
      );
      return SyncResult(SyncOutcome.failed, e);
    } finally {
      _syncing = false;
    }
  }

  /// Always re-signs-in rather than trusting currentSession != null, same
  /// reasoning as SupabaseBackend.signInAsKiosk's doc comment: a session
  /// persisted to disk from a previous run could still be sitting there
  /// unvalidated if main.dart's own sign-in attempt failed at cold boot
  /// (e.g. offline at startup) -- cheap enough to redo on every sync
  /// (manual / ~8h timer / connectivity-regained, never per-scan) that
  /// there's no reason to risk that class of bug here too.
  Future<void> _ensureSession() {
    return KioskBackend.instance.signInAsKiosk().timeout(const Duration(seconds: 8));
  }

  Future<void> _drainQueue() async {
    final pending = await LocalDatabase.instance.pendingAttendanceEvents();
    if (pending.isEmpty) return;

    final events = pending
        .map((row) => {
              'employee_id': row['employee_id'],
              'event_type': row['event_type'],
              'event_date': row['event_date'],
              'scanned_at': row['scanned_at'],
              'confidence': row['confidence'],
            })
        .toList();

    final results = await KioskBackend.instance.syncAttendanceBatch(events);

    // inserted/duplicate/rejected are all terminal -- safe to drop from the
    // local queue regardless of which one came back for a given row.
    for (final result in results) {
      await LocalDatabase.instance.removeQueuedEvent(
        employeeId: result['employee_id'] as String,
        eventDate: result['event_date'] as String,
        eventType: result['event_type'] as String,
      );
    }
  }

  Future<void> _reconcileToday() async {
    final rows = await KioskBackend.instance.fetchTodayAttendance();
    final byEmployee = <String, Map<String, Object?>>{};
    for (final row in rows) {
      final employeeId = row['employee_id'] as String;
      final eventType = row['event_type'] as String;
      final scannedAt = row['scanned_at'] as String;
      final entry = byEmployee.putIfAbsent(employeeId, () => {'checkInAt': null, 'hasCheckOut': false});
      if (eventType == 'check_in') {
        entry['checkInAt'] = scannedAt;
      } else if (eventType == 'check_out') {
        entry['hasCheckOut'] = true;
      }
    }

    if (byEmployee.isEmpty) return;
    final today = IstClock.todayKey();

    for (final entry in byEmployee.entries) {
      await LocalDatabase.instance.setAttendanceState(
        employeeId: entry.key,
        eventDate: today,
        checkInAt: entry.value['checkInAt'] as String?,
        hasCheckOut: entry.value['hasCheckOut'] as bool,
      );
    }
  }

  Future<void> _pruneOldAttendanceState() async {
    try {
      await LocalDatabase.instance
          .pruneAttendanceStateBefore(IstClock.dateKeyDaysAgo(attendanceStateRetentionDays));
    } catch (e, st) {
      await ErrorLogger.log(e, stackTrace: st, context: 'SyncService._pruneOldAttendanceState');
    }
  }
}
