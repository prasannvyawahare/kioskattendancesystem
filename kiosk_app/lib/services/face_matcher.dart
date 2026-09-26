import 'dart:math';

import '../models/enrolled_employee.dart';

class FaceMatch {
  FaceMatch(this.employee, this.similarity);
  final EnrolledEmployee employee;
  final double similarity;
}

/// In-memory cosine-similarity search over the embeddings synced down from
/// Supabase. An employee typically has several embeddings (one per
/// enrollment photo/angle); we match against the best of them.
class FaceMatcher {
  FaceMatcher({this.threshold = 0.65});

  /// Cosine similarity threshold above which a match is accepted. Start
  /// around 0.6-0.7 and tune based on real false-accept/false-reject rates
  /// once running on-device -- this can't be meaningfully tuned without a
  /// camera and real enrolled faces.
  final double threshold;

  List<EnrolledEmployee> _employees = [];

  /// Used by SyncService to decide whether a failed network refresh should
  /// fall back to LocalDatabase's cached roster (only worth doing if we
  /// don't already have a roster in memory, e.g. right after a cold boot).
  bool get hasEmployees => _employees.isNotEmpty;

  void updateEmployees(List<EnrolledEmployee> employees) {
    _employees = employees;
  }

  FaceMatch? match(List<double> probeEmbedding) {
    FaceMatch? best;

    for (final employee in _employees) {
      for (final embedding in employee.embeddings) {
        final similarity = _cosineSimilarity(probeEmbedding, embedding);
        if (best == null || similarity > best.similarity) {
          best = FaceMatch(employee, similarity);
        }
      }
    }

    if (best == null || best.similarity < threshold) return null;
    return best;
  }

  double _cosineSimilarity(List<double> a, List<double> b) {
    if (a.length != b.length || a.isEmpty) return -1;

    var dot = 0.0;
    var normA = 0.0;
    var normB = 0.0;
    for (var i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }

    if (normA == 0 || normB == 0) return -1;
    return dot / (sqrt(normA) * sqrt(normB));
  }
}
