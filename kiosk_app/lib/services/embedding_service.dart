import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

/// Loads the bundled face-embedding model and turns a cropped, upright face
/// image into a fixed-length embedding vector. This is the *only* place in
/// the app (enrollment sync and live recognition both call it) that runs
/// the embedding model, which is what keeps enrollment-time and
/// recognition-time embeddings comparable -- see the schema note in
/// supabase/migrations/0003_functions.sql for why that matters.
///
/// [inputSize] and [embeddingSize] must match whatever .tflite model you
/// place at [modelAssetPath] -- see kiosk_app/README.md for sourcing one.
/// [embeddingSize] must also match the `vector(512)` column in Postgres.
///
/// Currently pinned to the standard FaceNet model (160x160 input, 512-d
/// output) from the `face_verification` pub package, not the originally
/// planned 112x112/192-d MobileFaceNet -- see migration 0006.
class EmbeddingService {
  EmbeddingService._(this._interpreter);

  final Interpreter _interpreter;

  static const modelAssetPath = 'assets/models/face_embedding.tflite';
  static const inputSize = 160;
  static const embeddingSize = 512;

  static Future<EmbeddingService> load() async {
    final interpreter = await Interpreter.fromAsset(modelAssetPath);
    return EmbeddingService._(interpreter);
  }

  /// [faceImage] should already be a tightly cropped, upright face crop
  /// (see FaceImageUtils.cropToFace).
  List<double> embed(img.Image faceImage) {
    final resized = img.copyResize(faceImage, width: inputSize, height: inputSize);

    final input = [
      List.generate(
        inputSize,
        (y) => List.generate(inputSize, (x) {
          final pixel = resized.getPixel(x, y);
          return [
            (pixel.r - 127.5) / 128.0,
            (pixel.g - 127.5) / 128.0,
            (pixel.b - 127.5) / 128.0,
          ];
        }),
      ),
    ];

    final output = [List.filled(embeddingSize, 0.0)];

    _interpreter.run(input, output);

    return List<double>.from(output[0]);
  }

  void dispose() => _interpreter.close();
}
