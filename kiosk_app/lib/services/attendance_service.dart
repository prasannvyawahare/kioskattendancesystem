import '../models/enrolled_employee.dart';
import 'supabase_service.dart';

class AttendanceResult {
  AttendanceResult(this.employee, this.status);
  final EnrolledEmployee employee;

  /// 'check_in' | 'check_out' | 'already_completed'
  final String status;
}

/// Debounces repeat detections of the same person (so standing in front of
/// the camera for a few seconds doesn't fire multiple attendance calls),
/// then calls mark_attendance(), which makes the actual
/// check-in/check-out/already-completed decision atomically in Postgres --
/// see supabase/migrations/0003_functions.sql.
class AttendanceService {
  AttendanceService({this.cooldown = const Duration(seconds: 15)});

  final Duration cooldown;
  final Map<String, DateTime> _lastScanAt = {};

  Future<AttendanceResult?> handleMatch(EnrolledEmployee employee, double similarity) async {
    final now = DateTime.now();
    final last = _lastScanAt[employee.id];
    if (last != null && now.difference(last) < cooldown) {
      return null;
    }
    _lastScanAt[employee.id] = now;

    final status = await SupabaseService.instance.markAttendance(
      employee.id,
      confidence: similarity,
    );
    return AttendanceResult(employee, status);
  }
}
