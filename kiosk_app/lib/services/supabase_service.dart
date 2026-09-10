import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import '../models/enrolled_employee.dart';
import '../models/kiosk_settings.dart';
import '../models/member_summary.dart';

/// Thin wrapper around the Supabase client: kiosk auth, the two read paths
/// (enrolled employees for matching, pending employees for enrollment sync)
/// and the two write paths, both of which go through SECURITY DEFINER
/// Postgres functions rather than direct table writes (see
/// supabase/migrations/0003_functions.sql).
class SupabaseService {
  SupabaseService._();
  static final SupabaseService instance = SupabaseService._();

  SupabaseClient get client => Supabase.instance.client;

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
  Future<void> signInAsKiosk() async {
    await client.auth.signInWithPassword(
      email: KioskConfig.kioskEmail,
      password: KioskConfig.kioskPassword,
    );
  }

  /// Active, fully-enrolled employees plus every embedding produced from
  /// their enrollment photos -- this is what FaceMatcher compares live
  /// camera frames against.
  Future<List<EnrolledEmployee>> fetchEnrolledEmployees() async {
    final employeeRows = await client
        .from('employees')
        .select('id, full_name')
        .eq('is_active', true)
        .eq('embedding_status', 'completed') as List;

    final employees = <EnrolledEmployee>[];
    for (final row in employeeRows) {
      final employeeId = row['id'] as String;
      final embeddingRows = await client
          .from('face_embeddings')
          .select('embedding')
          .eq('employee_id', employeeId) as List;

      final embeddings = embeddingRows
          .map((row) => parsePgVector(row['embedding']))
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

  Future<List<Map<String, dynamic>>> fetchPendingEmployees() async {
    final rows = await client
        .from('employees')
        .select('id, full_name')
        .eq('is_active', true)
        .eq('embedding_status', 'pending') as List;
    return rows.cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> fetchEmployeePhotos(String employeeId) async {
    final rows = await client
        .from('employee_photos')
        .select('id, storage_path')
        .eq('employee_id', employeeId) as List;
    return rows.cast<Map<String, dynamic>>();
  }

  Future<Uint8List> downloadPhoto(String storagePath) {
    return client.storage.from('employee-photos').download(storagePath);
  }

  /// Returns 'check_in', 'check_out', or 'already_completed'.
  Future<String> markAttendance(String employeeId, {double? confidence}) async {
    final result = await client.rpc('mark_attendance', params: {
      'p_employee_id': employeeId,
      'p_confidence': confidence,
    });
    return result as String;
  }

  Future<void> recordFaceEmbedding({
    required String employeeId,
    required String photoId,
    required List<double> embedding,
  }) {
    return client.rpc('record_face_embedding', params: {
      'p_employee_id': employeeId,
      'p_photo_id': photoId,
      'p_embedding': embedding,
    });
  }

  Future<void> markEmbeddingFailed(String employeeId) {
    return client.rpc('mark_embedding_failed', params: {'p_employee_id': employeeId});
  }

  /// Admin-managed org name, greeting templates, and voice/enrollment
  /// toggles -- see supabase/migrations/0007_kiosk_enrollment.sql.
  Future<KioskSettings> fetchKioskSettings() async {
    final row = await client.from('kiosk_settings').select().single();
    return KioskSettings.fromRow(row);
  }

  /// Every active member regardless of recognition status, for
  /// MemberListScreen (unlike fetchEnrolledEmployees, which only returns
  /// members the matcher can actually recognize).
  Future<List<MemberSummary>> fetchAllMembers() async {
    final rows = await client
        .from('employees')
        .select('id, full_name, employee_code, department, embedding_status')
        .eq('is_active', true)
        .order('created_at', ascending: false) as List;
    return rows.cast<Map<String, dynamic>>().map(MemberSummary.fromRow).toList();
  }

  /// Fast pass/fail check for the PIN pad. The real authorization gate is
  /// enroll_member() re-checking the PIN itself -- this is just UI feedback.
  Future<bool> verifyEnrollmentPin(String pin) async {
    final result = await client.rpc('verify_enrollment_pin', params: {'p_pin': pin});
    return result as bool;
  }

  /// Creates a new member. Returns the new member's id.
  Future<String> enrollMember({
    required String pin,
    required String fullName,
    String? code,
    String? group,
  }) async {
    final result = await client.rpc('enroll_member', params: {
      'p_pin': pin,
      'p_full_name': fullName,
      'p_code': code,
      'p_group': group,
    });
    return result as String;
  }

  /// Edits a member's core fields. Re-verifies [pin] server-side, same as
  /// enrollMember.
  Future<void> updateMember({
    required String pin,
    required String employeeId,
    required String fullName,
    String? code,
    String? group,
  }) {
    return client.rpc('update_member', params: {
      'p_pin': pin,
      'p_employee_id': employeeId,
      'p_full_name': fullName,
      'p_code': code,
      'p_group': group,
    });
  }

  /// Deletes a member (cascades to their photos/embeddings). Re-verifies
  /// [pin] server-side, same as enrollMember.
  Future<void> deleteMember({required String pin, required String employeeId}) {
    return client.rpc('delete_member', params: {
      'p_pin': pin,
      'p_employee_id': employeeId,
    });
  }

  Future<String> uploadMemberPhoto(String employeeId, Uint8List jpegBytes) async {
    final path =
        '$employeeId/${DateTime.now().microsecondsSinceEpoch}.jpg';
    await client.storage.from('employee-photos').uploadBinary(
          path,
          jpegBytes,
          fileOptions: const FileOptions(contentType: 'image/jpeg'),
        );
    return path;
  }

  Future<String> recordMemberPhoto({
    required String employeeId,
    required String storagePath,
  }) async {
    final result = await client.rpc('record_member_photo', params: {
      'p_employee_id': employeeId,
      'p_storage_path': storagePath,
    });
    return result as String;
  }
}

/// PostgREST serializes pgvector's `vector` columns as their Postgres text
/// output (e.g. "[0.1,0.2,0.3]"), not a JSON array, so this always arrives
/// as a String over postgrest-dart. Handles a already-decoded List too, in
/// case that ever changes upstream.
List<double> parsePgVector(Object? value) {
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
