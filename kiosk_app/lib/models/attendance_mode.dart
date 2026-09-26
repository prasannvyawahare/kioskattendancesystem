/// Device-local attendance mode, set on-kiosk via DeviceSettingsScreen and
/// stored only in LocalDatabase's local_settings table -- never synced to
/// the shared `kiosk_settings` Postgres row or admin_panel, so different
/// kiosks can run different modes independently.
enum AttendanceMode {
  both,
  checkInOnly,
  checkOutOnly;

  /// Matches the `p_mode` values accepted by mark_attendance() and the
  /// branches in AttendanceDecisionEngine -- keep these three in sync.
  String toDbValue() {
    switch (this) {
      case AttendanceMode.both:
        return 'both';
      case AttendanceMode.checkInOnly:
        return 'check_in_only';
      case AttendanceMode.checkOutOnly:
        return 'check_out_only';
    }
  }

  static AttendanceMode fromDbValue(String? value) {
    switch (value) {
      case 'check_in_only':
        return AttendanceMode.checkInOnly;
      case 'check_out_only':
        return AttendanceMode.checkOutOnly;
      default:
        return AttendanceMode.both;
    }
  }
}
