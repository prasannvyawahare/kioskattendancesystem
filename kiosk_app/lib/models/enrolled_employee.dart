/// An employee whose enrollment is complete, cached in memory on the kiosk
/// with every embedding produced from their enrollment photos (one photo
/// can yield zero embeddings if no face was detected in it).
class EnrolledEmployee {
  EnrolledEmployee({
    required this.id,
    required this.fullName,
    required this.embeddings,
  });

  final String id;
  final String fullName;
  final List<List<double>> embeddings;
}
