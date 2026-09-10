/// Mirrors the single row in `kiosk_settings` (supabase/migrations/0007_kiosk_enrollment.sql).
/// Admin-managed: institution name, voice/enrollment toggles, and the
/// greeting templates GreetingService renders at check-in/check-out.
class KioskSettings {
  KioskSettings({
    required this.institutionName,
    required this.memberLabel,
    required this.voiceEnabled,
    required this.enrollmentEnabled,
    required this.checkinGreetingTemplate,
    required this.checkoutGreetingTemplate,
  });

  final String institutionName;
  final String memberLabel;
  final bool voiceEnabled;
  final bool enrollmentEnabled;
  final String checkinGreetingTemplate;
  final String checkoutGreetingTemplate;

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
