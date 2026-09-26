import 'dart:typed_data';

import '../models/enrolled_employee.dart';
import '../models/kiosk_settings.dart';
import '../models/member_summary.dart';

/// Everything the kiosk app needs from its backend, kept deliberately
/// storage-agnostic (plain Dart types in, plain Dart types/Maps out -- no
/// Supabase/Postgrest types in the signature) so SupabaseBackend
/// (services/supabase_backend.dart) can be swapped for a different
/// implementation (a plain REST API, say) later without touching any
/// screen or service that calls KioskBackend.instance.* -- only the
/// implementation class changes.
///
/// Every screen/service in this app must go through KioskBackend.instance,
/// never construct or reference a backend-specific client directly. To
/// swap backends, implement this interface and reassign `instance` (e.g.
/// in main() before runApp) -- nothing else in the app needs to change.
abstract class KioskBackend {
  static KioskBackend instance = _unconfigured;
  static const _unconfigured = _UnconfiguredBackend();

  /// Authenticates as the kiosk. Called at startup and again by
  /// SyncService before every sync, so implementations should be safe to
  /// call repeatedly (idempotent re-auth, not "already signed in" errors).
  Future<void> signInAsKiosk();

  /// Active, fully-enrolled employees plus every embedding produced from
  /// their enrollment photos -- what FaceMatcher compares live camera
  /// frames against.
  Future<List<EnrolledEmployee>> fetchEnrolledEmployees();

  /// Employees awaiting embedding (registered in admin_panel, photos not
  /// yet processed by this kiosk's EnrollmentSyncService). Each map has at
  /// least 'id' and 'full_name'.
  Future<List<Map<String, dynamic>>> fetchPendingEmployees();

  /// Enrollment photos for [employeeId] not yet turned into embeddings.
  /// Each map has at least 'id' and 'storage_path'.
  Future<List<Map<String, dynamic>>> fetchEmployeePhotos(String employeeId);

  Future<Uint8List> downloadPhoto(String storagePath);

  /// Returns 'check_in', 'check_out', or 'already_completed'. [mode] is
  /// the device-local AttendanceMode's db value ('both' |
  /// 'check_in_only' | 'check_out_only').
  Future<String> markAttendance(String employeeId, {double? confidence, String mode});

  Future<void> recordFaceEmbedding({
    required String employeeId,
    required String photoId,
    required List<double> embedding,
  });

  Future<void> markEmbeddingFailed(String employeeId);

  /// Admin-managed org name, greeting templates, and voice/enrollment
  /// toggles.
  Future<KioskSettings> fetchKioskSettings();

  /// Every active member regardless of recognition status.
  Future<List<MemberSummary>> fetchAllMembers();

  /// Fast pass/fail check for the PIN pad.
  Future<bool> verifyEnrollmentPin(String pin);

  /// Creates a new member. Returns the new member's id. [email]/[phone] and
  /// the mother/father contact fields mirror the admin-panel registration
  /// form (register-employee-form.tsx) so members added on-device carry the
  /// same fields as ones registered there.
  Future<String> enrollMember({
    required String pin,
    required String fullName,
    String? code,
    String? group,
    String? email,
    String? phone,
    String? motherName,
    String? motherPhone,
    String? motherEmail,
    String? fatherName,
    String? fatherPhone,
    String? fatherEmail,
  });

  Future<void> updateMember({
    required String pin,
    required String employeeId,
    required String fullName,
    String? code,
    String? group,
    String? email,
    String? phone,
    String? motherName,
    String? motherPhone,
    String? motherEmail,
    String? fatherName,
    String? fatherPhone,
    String? fatherEmail,
  });

  Future<void> deleteMember({required String pin, required String employeeId});

  Future<String> uploadMemberPhoto(String employeeId, Uint8List jpegBytes);

  Future<String> recordMemberPhoto({required String employeeId, required String storagePath});

  /// Pushes previously offline-queued attendance events (already decided
  /// by AttendanceDecisionEngine at scan time) for a deduped insert. Every
  /// entry in the returned list is terminal -- 'inserted', 'duplicate', or
  /// 'rejected' -- so the caller can drop all of them from its local
  /// queue. Each input map has employee_id/event_type/event_date/
  /// scanned_at/confidence.
  Future<List<Map<String, dynamic>>> syncAttendanceBatch(List<Map<String, dynamic>> events);

  /// Today's attendance events (server-side day boundary), each map with
  /// employee_id/event_type/scanned_at -- lets a kiosk reconcile its local
  /// attendance_state cache with anything it didn't personally witness
  /// (e.g. after a mid-day restart) before it potentially goes offline.
  Future<List<Map<String, dynamic>>> fetchTodayAttendance();
}

/// KioskBackend.instance's default value, so a bug in wiring (main.dart
/// failing to set the real backend before anything calls it) fails loudly
/// at the call site instead of silently returning empty data.
class _UnconfiguredBackend implements KioskBackend {
  const _UnconfiguredBackend();

  Never get _unconfigured => throw StateError(
        'KioskBackend.instance was never set -- main.dart must assign it '
        '(e.g. KioskBackend.instance = SupabaseBackend()) before runApp().',
      );

  @override
  Future<void> signInAsKiosk() => _unconfigured;
  @override
  Future<List<EnrolledEmployee>> fetchEnrolledEmployees() => _unconfigured;
  @override
  Future<List<Map<String, dynamic>>> fetchPendingEmployees() => _unconfigured;
  @override
  Future<List<Map<String, dynamic>>> fetchEmployeePhotos(String employeeId) => _unconfigured;
  @override
  Future<Uint8List> downloadPhoto(String storagePath) => _unconfigured;
  @override
  Future<String> markAttendance(String employeeId, {double? confidence, String mode = 'both'}) =>
      _unconfigured;
  @override
  Future<void> recordFaceEmbedding({
    required String employeeId,
    required String photoId,
    required List<double> embedding,
  }) =>
      _unconfigured;
  @override
  Future<void> markEmbeddingFailed(String employeeId) => _unconfigured;
  @override
  Future<KioskSettings> fetchKioskSettings() => _unconfigured;
  @override
  Future<List<MemberSummary>> fetchAllMembers() => _unconfigured;
  @override
  Future<bool> verifyEnrollmentPin(String pin) => _unconfigured;
  @override
  Future<String> enrollMember({
    required String pin,
    required String fullName,
    String? code,
    String? group,
    String? email,
    String? phone,
    String? motherName,
    String? motherPhone,
    String? motherEmail,
    String? fatherName,
    String? fatherPhone,
    String? fatherEmail,
  }) =>
      _unconfigured;
  @override
  Future<void> updateMember({
    required String pin,
    required String employeeId,
    required String fullName,
    String? code,
    String? group,
    String? email,
    String? phone,
    String? motherName,
    String? motherPhone,
    String? motherEmail,
    String? fatherName,
    String? fatherPhone,
    String? fatherEmail,
  }) =>
      _unconfigured;
  @override
  Future<void> deleteMember({required String pin, required String employeeId}) => _unconfigured;
  @override
  Future<String> uploadMemberPhoto(String employeeId, Uint8List jpegBytes) => _unconfigured;
  @override
  Future<String> recordMemberPhoto({required String employeeId, required String storagePath}) =>
      _unconfigured;
  @override
  Future<List<Map<String, dynamic>>> syncAttendanceBatch(List<Map<String, dynamic>> events) =>
      _unconfigured;
  @override
  Future<List<Map<String, dynamic>>> fetchTodayAttendance() => _unconfigured;
}

/// Thrown by KioskBackend implementations for an auth/authorization
/// failure (e.g. the kiosk's own session isn't valid), normalized across
/// backends so UI code (PinEntryScreen) can special-case it without
/// depending on a backend-specific exception type.
class BackendAuthException implements Exception {
  BackendAuthException(this.message);
  final String message;

  @override
  String toString() => 'BackendAuthException: $message';
}
