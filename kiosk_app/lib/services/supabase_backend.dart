import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import '../models/device_identity.dart';
import '../models/enrolled_employee.dart';
import '../models/kiosk_settings.dart';
import '../models/member_summary.dart';
import 'device_credentials_store.dart';
import 'error_logger.dart';
import 'kiosk_backend.dart';

/// The only file in this app allowed to import supabase_flutter or
/// reference Postgrest/Supabase types -- every other screen/service goes
/// through the storage-agnostic KioskBackend interface
/// (services/kiosk_backend.dart). Swapping backends later means writing a
/// new KioskBackend implementation and pointing KioskBackend.instance at
/// it in main.dart; nothing else in the app should need to change.
///
/// Auth, the read paths (enrolled employees for matching, pending
/// employees for enrollment sync), and the write paths all go through
/// SECURITY DEFINER Postgres functions rather than direct table writes
/// (see supabase/migrations/0003_functions.sql).
class SupabaseBackend implements KioskBackend {
  SupabaseClient get _client => Supabase.instance.client;

  /// Always re-authenticates rather than trusting a cached session:
  /// supabase_flutter persists sessions to disk across app restarts, so a
  /// session left over from an earlier test run (refresh token since
  /// rotated/invalidated by a concurrent login elsewhere, or otherwise
  /// stale) would sit there as non-null forever and get skipped by a
  /// currentSession != null guard -- every RPC then fails with the
  /// SECURITY DEFINER functions' "not authorized" (auth.uid() resolving to
  /// nothing valid), which looks identical to never having signed in at
  /// all. A fresh password sign-in every startup costs one extra request
  /// and removes that whole class of bug.
  @override
  Future<void> signInAsKiosk() async {
    // Paired (DeviceSetupScreen) credentials take priority over the
    // dart-define fallback -- a tablet that's been paired has an explicit,
    // admin-assigned identity that shouldn't be silently overridden by
    // whatever this particular build happened to be compiled with.
    final stored = await DeviceCredentialsStore.instance.read();
    final email = stored?.email ?? KioskConfig.kioskEmail;
    final password = stored?.password ?? KioskConfig.kioskPassword;
    if (email.isEmpty || password.isEmpty) {
      throw BackendAuthException('This device is not paired yet.');
    }
    await _client.auth.signInWithPassword(email: email, password: password);
  }

  @override
  Future<DeviceIdentity> verifyDeviceCredentials({
    required String email,
    required String password,
  }) async {
    try {
      await _client.auth.signInWithPassword(email: email, password: password);
    } on AuthException catch (e) {
      throw BackendAuthException(e.message);
    }

    try {
      return await fetchDeviceIdentity();
    } catch (_) {
      // Signed in with valid credentials for a non-kiosk account (or the
      // profile lookup itself failed) -- don't leave that session active.
      await _client.auth.signOut();
      rethrow;
    }
  }

  @override
  Future<DeviceIdentity> fetchDeviceIdentity() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) throw BackendAuthException('Not signed in');

    final row = await _client
        .from('profiles')
        .select('role, device_label, full_name, assigned_standard, assigned_section')
        .eq('id', uid)
        .single();

    if (row['role'] != 'kiosk') {
      throw BackendAuthException('That account is not a kiosk device.');
    }
    return DeviceIdentity.fromRow(row);
  }

  @override
  Future<void> signOut() => _client.auth.signOut();

  @override
  Future<List<EnrolledEmployee>> fetchEnrolledEmployees() async {
    final employeeRows = await _client
        .from('employees')
        .select('id, full_name')
        .eq('is_active', true)
        .eq('embedding_status', 'completed') as List;

    final employees = <EnrolledEmployee>[];
    for (final row in employeeRows) {
      final employeeId = row['id'] as String;
      final embeddingRows = await _client
          .from('face_embeddings')
          .select('embedding')
          .eq('employee_id', employeeId) as List;

      final embeddings = embeddingRows
          .map((row) => _parsePgVector(row['embedding']))
          .where((e) => e.isNotEmpty)
          .toList();

      if (embeddings.isEmpty) continue;

      employees.add(EnrolledEmployee(
        id: employeeId,
        fullName: row['full_name'] as String,
        embeddings: embeddings,
      ));
    }
    return employees;
  }

  @override
  Future<List<Map<String, dynamic>>> fetchPendingEmployees() async {
    final rows = await _client
        .from('employees')
        .select('id, full_name')
        .eq('is_active', true)
        .eq('embedding_status', 'pending') as List;
    return rows.cast<Map<String, dynamic>>();
  }

  @override
  Future<List<Map<String, dynamic>>> fetchEmployeePhotos(String employeeId) async {
    final rows = await _client
        .from('employee_photos')
        .select('id, storage_path')
        .eq('employee_id', employeeId) as List;
    return rows.cast<Map<String, dynamic>>();
  }

  @override
  Future<Uint8List> downloadPhoto(String storagePath) {
    return _client.storage.from('employee-photos').download(storagePath);
  }

  @override
  Future<String> markAttendance(
    String employeeId, {
    double? confidence,
    String mode = 'both',
  }) async {
    final result = await _client.rpc('mark_attendance', params: {
      'p_employee_id': employeeId,
      'p_confidence': confidence,
      'p_mode': mode,
    });
    return result as String;
  }

  @override
  Future<List<Map<String, dynamic>>> syncAttendanceBatch(
    List<Map<String, dynamic>> events,
  ) async {
    final result = await _client.rpc('sync_attendance_batch', params: {
      'p_events': events,
    });
    return (result as List).cast<Map<String, dynamic>>();
  }

  @override
  Future<List<Map<String, dynamic>>> fetchTodayAttendance() async {
    final result = await _client.rpc('fetch_today_attendance');
    return (result as List).cast<Map<String, dynamic>>();
  }

  @override
  Future<void> recordFaceEmbedding({
    required String employeeId,
    required String photoId,
    required List<double> embedding,
  }) {
    return _client.rpc('record_face_embedding', params: {
      'p_employee_id': employeeId,
      'p_photo_id': photoId,
      'p_embedding': embedding,
    });
  }

  @override
  Future<void> markEmbeddingFailed(String employeeId) {
    return _client.rpc('mark_embedding_failed', params: {'p_employee_id': employeeId});
  }

  /// Admin-managed org name, greeting templates, and voice/enrollment
  /// toggles -- see supabase/migrations/0007_kiosk_enrollment.sql.
  @override
  Future<KioskSettings> fetchKioskSettings() async {
    final row = await _client.from('kiosk_settings').select().single();
    return KioskSettings.fromRow(row);
  }

  /// Every active member regardless of recognition status, for
  /// MemberListScreen (unlike fetchEnrolledEmployees, which only returns
  /// members the matcher can actually recognize).
  @override
  Future<List<MemberSummary>> fetchAllMembers() async {
    final rows = await _client
        .from('employees')
        .select(
          'id, full_name, employee_code, department, email, phone, standard, section, '
          'mother_name, mother_phone, mother_email, '
          'father_name, father_phone, father_email, embedding_status',
        )
        .eq('is_active', true)
        .order('created_at', ascending: false) as List;
    return rows.cast<Map<String, dynamic>>().map(MemberSummary.fromRow).toList();
  }

  /// Fast pass/fail check for the PIN pad. The real authorization gate is
  /// enroll_member() re-checking the PIN itself -- this is just UI
  /// feedback. Normalizes the SECURITY DEFINER functions' "not authorized"
  /// (kiosk session invalid) into BackendAuthException so UI code doesn't
  /// need to know this is Supabase/Postgrest underneath.
  @override
  Future<bool> verifyEnrollmentPin(String pin) async {
    try {
      final result = await _client.rpc('verify_enrollment_pin', params: {'p_pin': pin});
      return result as bool;
    } on PostgrestException catch (e) {
      if (e.message.contains('not authorized')) {
        throw BackendAuthException(e.message);
      }
      rethrow;
    }
  }

  @override
  Future<String> enrollMember({
    required String pin,
    required String fullName,
    String? code,
    String? group,
    String? email,
    String? phone,
    String? standard,
    String? section,
    String? motherName,
    String? motherPhone,
    String? motherEmail,
    String? fatherName,
    String? fatherPhone,
    String? fatherEmail,
  }) async {
    final result = await _client.rpc('enroll_member', params: {
      'p_pin': pin,
      'p_full_name': fullName,
      'p_code': code,
      'p_group': group,
      'p_email': email,
      'p_phone': phone,
      'p_standard': standard,
      'p_section': section,
      'p_mother_name': motherName,
      'p_mother_phone': motherPhone,
      'p_mother_email': motherEmail,
      'p_father_name': fatherName,
      'p_father_phone': fatherPhone,
      'p_father_email': fatherEmail,
    });
    return result as String;
  }

  /// Edits a member's fields. Re-verifies [pin] server-side, same as
  /// enrollMember.
  @override
  Future<void> updateMember({
    required String pin,
    required String employeeId,
    required String fullName,
    String? code,
    String? group,
    String? email,
    String? phone,
    String? standard,
    String? section,
    String? motherName,
    String? motherPhone,
    String? motherEmail,
    String? fatherName,
    String? fatherPhone,
    String? fatherEmail,
  }) {
    return _client.rpc('update_member', params: {
      'p_pin': pin,
      'p_employee_id': employeeId,
      'p_full_name': fullName,
      'p_code': code,
      'p_group': group,
      'p_email': email,
      'p_phone': phone,
      'p_standard': standard,
      'p_section': section,
      'p_mother_name': motherName,
      'p_mother_phone': motherPhone,
      'p_mother_email': motherEmail,
      'p_father_name': fatherName,
      'p_father_phone': fatherPhone,
      'p_father_email': fatherEmail,
    });
  }

  /// Deletes a member (DB row cascades to their photos/embeddings).
  /// Re-verifies [pin] server-side, same as enrollMember. Also best-effort
  /// removes the member's actual photo files from Storage -- the FK cascade
  /// only ever removed the employee_photos rows, never the blobs
  /// themselves, leaving them orphaned forever (see
  /// supabase/migrations/0017_hardening.sql, which grants the kiosk the
  /// storage DELETE policy this now relies on).
  @override
  Future<void> deleteMember({required String pin, required String employeeId}) async {
    await _client.rpc('delete_member', params: {
      'p_pin': pin,
      'p_employee_id': employeeId,
    });
    await _deleteMemberPhotos(employeeId);
  }

  /// Storage cleanup is deliberately best-effort and never allowed to turn
  /// an already-successful member deletion into a user-visible error --
  /// callers only care that the member record is gone.
  Future<void> _deleteMemberPhotos(String employeeId) async {
    try {
      final objects = await _client.storage.from('employee-photos').list(path: employeeId);
      if (objects.isEmpty) return;
      await _client.storage
          .from('employee-photos')
          .remove(objects.map((o) => '$employeeId/${o.name}').toList());
    } catch (e, st) {
      await ErrorLogger.log(e, stackTrace: st, context: 'SupabaseBackend._deleteMemberPhotos');
    }
  }

  @override
  Future<String> uploadMemberPhoto(String employeeId, Uint8List jpegBytes) async {
    final path = '$employeeId/${DateTime.now().microsecondsSinceEpoch}.jpg';
    await _client.storage.from('employee-photos').uploadBinary(
          path,
          jpegBytes,
          fileOptions: const FileOptions(contentType: 'image/jpeg'),
        );
    return path;
  }

  @override
  Future<String> recordMemberPhoto({
    required String employeeId,
    required String storagePath,
  }) async {
    final result = await _client.rpc('record_member_photo', params: {
      'p_employee_id': employeeId,
      'p_storage_path': storagePath,
    });
    return result as String;
  }
}

/// PostgREST serializes pgvector's `vector` columns as their Postgres text
/// output (e.g. "[0.1,0.2,0.3]"), not a JSON array, so this always arrives
/// as a String over postgrest-dart. Handles an already-decoded List too, in
/// case that ever changes upstream.
List<double> _parsePgVector(Object? value) {
  if (value == null) return const [];
  if (value is List) {
    return value.map((v) => (v as num).toDouble()).toList();
  }
  final text = value.toString().trim();
  final inner = text.startsWith('[') && text.endsWith(']')
      ? text.substring(1, text.length - 1)
      : text;
  if (inner.isEmpty) return const [];
  return inner.split(',').map((s) => double.parse(s.trim())).toList();
}
