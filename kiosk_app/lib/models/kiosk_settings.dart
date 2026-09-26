/// Mirrors the single row in `kiosk_settings` (supabase/migrations/0007_kiosk_enrollment.sql).
/// Admin-managed: institution name, voice/enrollment toggles, the greeting
/// templates GreetingService renders at check-in/check-out, and the kiosk
/// timing knobs below (supabase/migrations/0015_configurable_timings.sql).
class KioskSettings {
  KioskSettings({
    required this.institutionName,
    required this.memberLabel,
    required this.voiceEnabled,
    required this.enrollmentEnabled,
    required this.checkinGreetingTemplate,
    required this.checkoutGreetingTemplate,
    this.enrollmentPinHash,
    this.onlineTimeoutSeconds = 5,
    this.minScanGapMinutes = 10,
    this.syncIntervalHours = 8,
    this.refreshIntervalSeconds = 60,
  });

  final String institutionName;
  final String memberLabel;
  final bool voiceEnabled;
  final bool enrollmentEnabled;
  final String checkinGreetingTemplate;
  final String checkoutGreetingTemplate;

  /// The bcrypt hash `verify_enrollment_pin()` checks against server-side
  /// -- already included in every `select()` of this row under the kiosk's
  /// RLS policy (kiosk_settings_kiosk_select grants full-row SELECT), just
  /// unused until PinVerificationService started caching it for offline PIN
  /// checks. Never the plaintext PIN.
  final String? enrollmentPinHash;

  /// How long AttendanceService/PinVerificationService wait for the server
  /// before falling back to their offline path. See [onlineTimeout].
  final int onlineTimeoutSeconds;

  /// Minimum gap between a check-in and check-out for the same person.
  /// Also enforced server-side in mark_attendance() -- this is the same
  /// value, just mirrored for AttendanceDecisionEngine's offline decision.
  /// See [minScanGap].
  final int minScanGapMinutes;

  /// How often SyncService auto-syncs queued offline attendance in the
  /// background. See [syncInterval].
  final int syncIntervalHours;

  /// How often the kiosk re-polls the employee roster, member list, and
  /// this settings row itself. See [refreshInterval].
  final int refreshIntervalSeconds;

  Duration get onlineTimeout => Duration(seconds: onlineTimeoutSeconds);
  Duration get minScanGap => Duration(minutes: minScanGapMinutes);
  Duration get syncInterval => Duration(hours: syncIntervalHours);
  Duration get refreshInterval => Duration(seconds: refreshIntervalSeconds);

  factory KioskSettings.fromRow(Map<String, dynamic> row) {
    return KioskSettings(
      institutionName: row['institution_name'] as String? ?? 'Your Organization',
      memberLabel: row['member_label'] as String? ?? 'Member',
      voiceEnabled: row['voice_enabled'] as bool? ?? true,
      enrollmentEnabled: row['enrollment_enabled'] as bool? ?? true,
      checkinGreetingTemplate: row['checkin_greeting_template'] as String? ??
          'Hello {name}, {time_greeting}! Welcome back to {institution}.',
      checkoutGreetingTemplate:
          row['checkout_greeting_template'] as String? ?? 'Goodbye {name}, see you soon!',
      enrollmentPinHash: row['enrollment_pin_hash'] as String?,
      onlineTimeoutSeconds: (row['online_timeout_seconds'] as num?)?.toInt() ?? 5,
      minScanGapMinutes: (row['min_scan_gap_minutes'] as num?)?.toInt() ?? 10,
      syncIntervalHours: (row['sync_interval_hours'] as num?)?.toInt() ?? 8,
      refreshIntervalSeconds: (row['refresh_interval_seconds'] as num?)?.toInt() ?? 60,
    );
  }

  static final defaults = KioskSettings(
    institutionName: 'Your Organization',
    memberLabel: 'Member',
    voiceEnabled: true,
    enrollmentEnabled: true,
    checkinGreetingTemplate: 'Hello {name}, {time_greeting}! Welcome back to {institution}.',
    checkoutGreetingTemplate: 'Goodbye {name}, see you soon!',
  );
}
