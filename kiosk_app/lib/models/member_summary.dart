/// A row for MemberListScreen -- every active member regardless of
/// recognition status, unlike EnrolledEmployee (which only exists for
/// members recognition is actually possible for).
class MemberSummary {
  MemberSummary({
    required this.id,
    required this.fullName,
    required this.code,
    required this.group,
    required this.embeddingStatus,
    this.email,
    this.phone,
    this.standard,
    this.section,
    this.motherName,
    this.motherPhone,
    this.motherEmail,
    this.fatherName,
    this.fatherPhone,
    this.fatherEmail,
  });

  final String id;
  final String fullName;
  final String? code;
  final String? group;

  /// 'pending' | 'processing' | 'completed' | 'failed'
  final String embeddingStatus;

  final String? email;
  final String? phone;
  final String? standard;
  final String? section;
  final String? motherName;
  final String? motherPhone;
  final String? motherEmail;
  final String? fatherName;
  final String? fatherPhone;
  final String? fatherEmail;

  factory MemberSummary.fromRow(Map<String, dynamic> row) {
    return MemberSummary(
      id: row['id'] as String,
      fullName: row['full_name'] as String,
      code: row['employee_code'] as String?,
      group: row['department'] as String?,
      embeddingStatus: row['embedding_status'] as String,
      email: row['email'] as String?,
      phone: row['phone'] as String?,
      standard: row['standard'] as String?,
      section: row['section'] as String?,
      motherName: row['mother_name'] as String?,
      motherPhone: row['mother_phone'] as String?,
      motherEmail: row['mother_email'] as String?,
      fatherName: row['father_name'] as String?,
      fatherPhone: row['father_phone'] as String?,
      fatherEmail: row['father_email'] as String?,
    );
  }
}
