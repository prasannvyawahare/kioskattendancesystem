import 'dart:io';

import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

import 'embedding_service.dart';
import 'face_image_utils.dart';
import 'supabase_service.dart';

/// Background job that turns newly-registered employees' enrollment photos
/// (captured in the admin panel, containing no embeddings of their own)
/// into face embeddings, using the exact same detector + embedding model as
/// live recognition (see EmbeddingService's doc comment for why that
/// consistency matters).
class EnrollmentSyncService {
  EnrollmentSyncService({
    required this.embeddingService,
    this.pollInterval = const Duration(seconds: 45),
  });

  final EmbeddingService embeddingService;
  final Duration pollInterval;

  final FaceDetector _detector = FaceDetector(
    options: FaceDetectorOptions(performanceMode: FaceDetectorMode.accurate),
  );

  bool _running = false;

  void start() {
    if (_running) return;
    _running = true;
    _loop();
  }

  void stop() => _running = false;

  Future<void> _loop() async {
    while (_running) {
      try {
        await syncOnce();
      } catch (_) {
        // Best-effort background job -- swallow and retry next tick rather
        // than crashing the kiosk over a transient network/storage error.
      }
      await Future<void>.delayed(pollInterval);
    }
  }

  Future<void> syncOnce() async {
    final pending = await SupabaseService.instance.fetchPendingEmployees();

    for (final employee in pending) {
      final employeeId = employee['id'] as String;
      final photos = await SupabaseService.instance.fetchEmployeePhotos(employeeId);

      if (photos.isEmpty) continue;

      var producedAny = false;
      for (final photo in photos) {
        final photoId = photo['id'] as String;
        final storagePath = photo['storage_path'] as String;

        final embedding = await _embedPhoto(storagePath);
        if (embedding == null) continue;

        await SupabaseService.instance.recordFaceEmbedding(
          employeeId: employeeId,
          photoId: photoId,
          embedding: embedding,
        );
        producedAny = true;
      }

      if (!producedAny) {
        await SupabaseService.instance.markEmbeddingFailed(employeeId);
      }
    }
  }

  Future<List<double>?> _embedPhoto(String storagePath) async {
    final bytes = await SupabaseService.instance.downloadPhoto(storagePath);

    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}/enroll_${DateTime.now().microsecondsSinceEpoch}.jpg');
    await file.writeAsBytes(bytes);

    try {
      final inputImage = InputImage.fromFilePath(file.path);
      final faces = await _detector.processImage(inputImage);
      if (faces.isEmpty) return null;

      // Largest face in the photo, in case of stray background faces.
      faces.sort((a, b) => (b.boundingBox.width * b.boundingBox.height)
          .compareTo(a.boundingBox.width * a.boundingBox.height));
      final face = faces.first;

      final decoded = img.decodeImage(bytes);
      if (decoded == null) return null;

      final cropped = FaceImageUtils.cropToFace(decoded, face.boundingBox);
      return embeddingService.embed(cropped);
    } finally {
      if (await file.exists()) await file.delete();
    }
  }

  void dispose() => _detector.close();
}
