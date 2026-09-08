import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import '../models/enrolled_employee.dart';

/// Thin wrapper around the Supabase client: kiosk auth, the two read paths
/// (enrolled employees for matching, pending employees for enrollment sync)
/// and the two write paths, both of which go through SECURITY DEFINER
/// Postgres functions rather than direct table writes (see
/// supabase/migrations/0003_functions.sql).
class SupabaseService {
  SupabaseService._();
  static final SupabaseService instance = SupabaseService._();

  SupabaseClient get client => Supabase.instance.client;

  Future<void> signInAsKiosk() async {
    if (client.auth.currentSession != null) return;
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
