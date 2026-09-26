import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/enrolled_employee.dart';
import '../models/member_summary.dart';

/// How long attendance_state rows are kept locally after their day -- only
/// today's (and briefly yesterday's, around midnight) rows are ever read,
/// so this just bounds an otherwise-unbounded one-row-per-employee-per-day
/// table. Pruned on cold boot and on every SyncService.syncNow.
const attendanceStateRetentionDays = 7;

/// The kiosk's offline store: everything needed to keep matching and
/// attendance-marking working with no network, plus the queue of events
/// produced while offline and waiting for SyncService to push them.
///
/// Every write to attendance_state/attendance_queue MUST go through the
/// upsert-style helpers below (insert with ConflictAlgorithm.replace on the
/// declared primary key) -- that's what makes re-deciding after a restart
/// idempotent instead of double-booking a check-in/check-out, since the PKs
/// mirror attendance_logs' own `unique (employee_id, event_date,
/// event_type)` constraint.
class LocalDatabase {
  LocalDatabase._();
  static final LocalDatabase instance = LocalDatabase._();

  Database? _db;

  Database get _database {
    final db = _db;
    if (db == null) {
      throw StateError('LocalDatabase.open() must be awaited before use');
    }
    return db;
  }

  Future<void> open() async {
    if (_db != null) return;
    final dbPath = await getDatabasesPath();
    _db = await openDatabase(
      p.join(dbPath, 'kiosk_offline.db'),
      version: 3,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE cached_employees (
            id TEXT PRIMARY KEY,
            full_name TEXT NOT NULL,
            updated_at TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE cached_embeddings (
            id TEXT PRIMARY KEY,
            employee_id TEXT NOT NULL,
            embedding TEXT NOT NULL
          )
        ''');
        await db.execute(
          'CREATE INDEX cached_embeddings_employee_idx ON cached_embeddings (employee_id)',
        );
        await db.execute('''
          CREATE TABLE attendance_state (
            employee_id TEXT NOT NULL,
            event_date TEXT NOT NULL,
            check_in_at TEXT,
            has_check_out INTEGER NOT NULL DEFAULT 0,
            PRIMARY KEY (employee_id, event_date)
          )
        ''');
        await db.execute('''
          CREATE TABLE attendance_queue (
            employee_id TEXT NOT NULL,
            event_date TEXT NOT NULL,
            event_type TEXT NOT NULL,
            scanned_at TEXT NOT NULL,
            confidence REAL,
            PRIMARY KEY (employee_id, event_date, event_type)
          )
        ''');
        await db.execute('''
          CREATE TABLE local_settings (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
          )
        ''');
        await db.execute(_cachedMembersTableSql);
        await db.execute(_errorLogsTableSql);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        // v1 -> v2: MemberListScreen originally had no offline fallback at
        // all (fetchAllMembers() was online-only) -- adds a cache for it,
        // same write-through/fallback pattern as cached_employees.
        if (oldVersion < 2) {
          await db.execute(_cachedMembersTableSql);
        }
        // v2 -> v3: persistent local error log, written by ErrorLogger
        // (services/error_logger.dart) from main.dart's global error
        // handlers plus a handful of previously-silent catch blocks, so
        // field issues on an unattended kiosk are diagnosable from
        // DeviceSettingsScreen instead of only via adb logcat.
        if (oldVersion < 3) {
          await db.execute(_errorLogsTableSql);
        }
      },
    );
  }

  static const _cachedMembersTableSql = '''
    CREATE TABLE cached_members (
      id TEXT PRIMARY KEY,
      full_name TEXT NOT NULL,
      code TEXT,
      group_name TEXT,
      embedding_status TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
  ''';

  static const _errorLogsTableSql = '''
    CREATE TABLE error_logs (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      logged_at TEXT NOT NULL,
      message TEXT NOT NULL,
      stack_trace TEXT,
      context TEXT
    )
  ''';

  // ---- cached roster (for offline matching, survives restarts) ----

  Future<void> replaceCachedEmployees(List<EnrolledEmployee> employees) async {
    final now = DateTime.now().toIso8601String();
    await _database.transaction((txn) async {
      await txn.delete('cached_employees');
      await txn.delete('cached_embeddings');
      for (final employee in employees) {
        await txn.insert('cached_employees', {
          'id': employee.id,
          'full_name': employee.fullName,
          'updated_at': now,
        });
        for (var i = 0; i < employee.embeddings.length; i++) {
          await txn.insert('cached_embeddings', {
            'id': '${employee.id}_$i',
            'employee_id': employee.id,
            'embedding': jsonEncode(employee.embeddings[i]),
          });
        }
      }
    });
  }

  Future<List<EnrolledEmployee>> loadCachedEmployees() async {
    final employeeRows = await _database.query('cached_employees');
    final employees = <EnrolledEmployee>[];
    for (final row in employeeRows) {
      final employeeId = row['id'] as String;
      final embeddingRows = await _database.query(
        'cached_embeddings',
        where: 'employee_id = ?',
        whereArgs: [employeeId],
      );
      final embeddings = embeddingRows
          .map((r) => (jsonDecode(r['embedding'] as String) as List)
              .map((v) => (v as num).toDouble())
              .toList())
          .toList();
      employees.add(EnrolledEmployee(
        id: employeeId,
        fullName: row['full_name'] as String,
        embeddings: embeddings,
      ));
    }
    return employees;
  }

  // ---- cached member list (for MemberListScreen offline fallback) ----

  Future<void> replaceCachedMembers(List<MemberSummary> members) async {
    final now = DateTime.now().toIso8601String();
    await _database.transaction((txn) async {
      await txn.delete('cached_members');
      for (final member in members) {
        await txn.insert('cached_members', {
          'id': member.id,
          'full_name': member.fullName,
          'code': member.code,
          'group_name': member.group,
          'embedding_status': member.embeddingStatus,
          'updated_at': now,
        });
      }
    });
  }

  Future<List<MemberSummary>> loadCachedMembers() async {
    final rows = await _database.query('cached_members', orderBy: 'full_name');
    return rows
        .map((row) => MemberSummary(
              id: row['id'] as String,
              fullName: row['full_name'] as String,
              code: row['code'] as String?,
              group: row['group_name'] as String?,
              embeddingStatus: row['embedding_status'] as String,
            ))
        .toList();
  }

  // ---- per-employee-per-day decision cache ----

  Future<Map<String, Object?>?> getAttendanceState(String employeeId, String eventDate) async {
    final rows = await _database.query(
      'attendance_state',
      where: 'employee_id = ? AND event_date = ?',
      whereArgs: [employeeId, eventDate],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<void> upsertAttendanceState({
    required String employeeId,
    required String eventDate,
    String? checkInAt,
    bool? hasCheckOut,
  }) async {
    final existing = await getAttendanceState(employeeId, eventDate);
    await _database.insert(
      'attendance_state',
      {
        'employee_id': employeeId,
        'event_date': eventDate,
        'check_in_at': checkInAt ?? existing?['check_in_at'] as String?,
        'has_check_out':
            (hasCheckOut ?? ((existing?['has_check_out'] as int?) == 1)) ? 1 : 0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Overwrites today's state for [employeeId] wholesale -- used to
  /// reconcile from an authoritative server answer (online scan result, or
  /// fetch_today_attendance() during sync), where the server's view should
  /// win outright rather than being merged field-by-field.
  Future<void> setAttendanceState({
    required String employeeId,
    required String eventDate,
    String? checkInAt,
    required bool hasCheckOut,
  }) {
    return _database.insert(
      'attendance_state',
      {
        'employee_id': employeeId,
        'event_date': eventDate,
        'check_in_at': checkInAt,
        'has_check_out': hasCheckOut ? 1 : 0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> pruneAttendanceStateBefore(String eventDate) {
    return _database.delete(
      'attendance_state',
      where: 'event_date < ?',
      whereArgs: [eventDate],
    );
  }

  // ---- offline event queue ----

  Future<void> enqueueAttendanceEvent({
    required String employeeId,
    required String eventDate,
    required String eventType,
    required String scannedAt,
    double? confidence,
  }) {
    return _database.insert(
      'attendance_queue',
      {
        'employee_id': employeeId,
        'event_date': eventDate,
        'event_type': eventType,
        'scanned_at': scannedAt,
        'confidence': confidence,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, Object?>>> pendingAttendanceEvents({int limit = 200}) {
    return _database.query('attendance_queue', limit: limit);
  }

  Future<int> pendingAttendanceCount() async {
    final result =
        await _database.rawQuery('SELECT COUNT(*) AS c FROM attendance_queue');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<void> removeQueuedEvent({
    required String employeeId,
    required String eventDate,
    required String eventType,
  }) {
    return _database.delete(
      'attendance_queue',
      where: 'employee_id = ? AND event_date = ? AND event_type = ?',
      whereArgs: [employeeId, eventDate, eventType],
    );
  }

  // ---- local key/value settings ----

  Future<String?> getSetting(String key) async {
    final rows = await _database.query(
      'local_settings',
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['value'] as String?;
  }

  Future<void> setSetting(String key, String value) {
    return _database.insert(
      'local_settings',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // ---- persistent error log (see services/error_logger.dart) ----

  Future<void> insertErrorLog({
    required String loggedAt,
    required String message,
    String? stackTrace,
    String? context,
  }) {
    return _database.insert('error_logs', {
      'logged_at': loggedAt,
      'message': message,
      'stack_trace': stackTrace,
      'context': context,
    });
  }

  Future<List<Map<String, Object?>>> recentErrorLogs({int limit = 50}) {
    return _database.query('error_logs', orderBy: 'id DESC', limit: limit);
  }

  Future<void> clearErrorLogs() {
    return _database.delete('error_logs');
  }
}
