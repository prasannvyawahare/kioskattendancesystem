/// This kiosk's own identity, as recorded in its profiles row (see
/// supabase/migrations/0026_kiosk_device_scoping.sql). Both [standard] and
/// [section] null means unrestricted -- this device sees every class.
class DeviceIdentity {
  const DeviceIdentity({
    required this.label,
    required this.standard,
    required this.section,
  });

  final String label;
  final String? standard;
  final String? section;

  bool get isClassScoped => standard != null || section != null;

  /// e.g. "12 - A", "12" (standard only), or null when unrestricted.
  String? get classLabel {
    if (!isClassScoped) return null;
    if (standard != null && section != null) return '$standard - $section';
    return standard ?? section;
  }

  factory DeviceIdentity.fromRow(Map<String, dynamic> row) {
    return DeviceIdentity(
      label: (row['device_label'] as String?) ?? (row['full_name'] as String?) ?? 'This device',
      standard: row['assigned_standard'] as String?,
      section: row['assigned_section'] as String?,
    );
  }
}
