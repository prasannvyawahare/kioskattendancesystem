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
  });

  final String id;
  final String fullName;
  final String? code;
  final String? group;

  /// 'pending' | 'processing' | 'completed' | 'failed'
  final String embeddingStatus;

  factory MemberSummary.fromRow(Map<String, dynamic> row) {
    return MemberSummary(
      id: row['id'] as String,
      fullName: row['full_name'] as String,
      code: row['employee_code'] as String?,
      group: row['department'] as String?,
      embeddingStatus: row['embedding_status'] as String,
    );
  }
}
