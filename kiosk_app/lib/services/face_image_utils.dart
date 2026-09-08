import 'dart:typed_data';
import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;

/// Camera-frame -> ML Kit `InputImage` / cropped RGB face image conversion.
///
/// This file is Android-only (the kiosk targets an Android tablet) and is
/// the single most likely place to need on-device tuning: exact YUV plane
/// layout, sensor rotation, and mirroring vary by manufacturer in ways that
/// are only really verifiable on real hardware, which wasn't available
/// while writing this. If detected faces look correctly boxed on-screen but
/// recognition accuracy is poor, start by checking `rotationDegrees` below
/// against your device's actual mounting orientation.
class FaceImageUtils {
  FaceImageUtils._();

  /// Builds the InputImage ML Kit's FaceDetector expects, by re-packing the
  /// camera plugin's YUV_420_888 planes into NV21 (Android's face detector
  /// expects NV21/YUV; passing YUV_420_888 planes through directly is not
  /// reliably supported across devices).
  static InputImage? toInputImage(CameraImage cameraImage, CameraDescription camera) {
    final rotation = InputImageRotationValue.fromRawValue(camera.sensorOrientation);
    if (rotation == null) return null;
    if (cameraImage.planes.length < 3) return null;

    final nv21 = _yuv420ToNv21(cameraImage);

    return InputImage.fromBytes(
      bytes: nv21,
      metadata: InputImageMetadata(
        size: Size(cameraImage.width.toDouble(), cameraImage.height.toDouble()),
        rotation: rotation,
        format: InputImageFormat.nv21,
        bytesPerRow: cameraImage.width,
      ),
    );
  }

  /// Converts the full camera frame to RGB and rotates it to match the
  /// orientation ML Kit assumed when it returned `Face.boundingBox` (see
  /// [toInputImage]'s `rotation`), so cropping with that box lines up.
  static img.Image toUprightRgbImage(CameraImage cameraImage, CameraDescription camera) {
    final rgb = _yuv420ToRgbImage(cameraImage);
    final degrees = camera.sensorOrientation;
    if (degrees == 0) return rgb;
    return img.copyRotate(rgb, angle: degrees);
  }

  static img.Image cropToFace(
    img.Image source,
    Rect boundingBox, {
    double padding = 0.25,
  }) {
    final padX = boundingBox.width * padding;
    final padY = boundingBox.height * padding;

    final left = (boundingBox.left - padX).clamp(0, source.width.toDouble()).toInt();
    final top = (boundingBox.top - padY).clamp(0, source.height.toDouble()).toInt();
    final right = (boundingBox.right + padX).clamp(0, source.width.toDouble()).toInt();
    final bottom = (boundingBox.bottom + padY).clamp(0, source.height.toDouble()).toInt();

    final width = (right - left).clamp(1, source.width);
    final height = (bottom - top).clamp(1, source.height);

    return img.copyCrop(source, x: left, y: top, width: width, height: height);
  }

  static Uint8List _yuv420ToNv21(CameraImage image) {
    final width = image.width;
    final height = image.height;
    final yPlane = image.planes[0];
    final uPlane = image.planes[1];
    final vPlane = image.planes[2];

    final ySize = width * height;
    final uvSize = width * height ~/ 2;
    final nv21 = Uint8List(ySize + uvSize);

    var offset = 0;
    for (var row = 0; row < height; row++) {
      final rowStart = row * yPlane.bytesPerRow;
      nv21.setRange(offset, offset + width, yPlane.bytes, rowStart);
      offset += width;
    }

    final uvRowStride = uPlane.bytesPerRow;
    final uvPixelStride = uPlane.bytesPerPixel ?? 1;
    var uvOffset = ySize;
    for (var row = 0; row < height ~/ 2; row++) {
      for (var col = 0; col < width ~/ 2; col++) {
        final uIndex = row * uvRowStride + col * uvPixelStride;
        final vIndex = row * vPlane.bytesPerRow + col * (vPlane.bytesPerPixel ?? 1);
        nv21[uvOffset++] = vPlane.bytes[vIndex];
        nv21[uvOffset++] = uPlane.bytes[uIndex];
      }
    }

    return nv21;
  }

  static img.Image _yuv420ToRgbImage(CameraImage cameraImage) {
    final width = cameraImage.width;
    final height = cameraImage.height;

    final yPlane = cameraImage.planes[0];
    final uPlane = cameraImage.planes[1];
    final vPlane = cameraImage.planes[2];

    final out = img.Image(width: width, height: height);

    final uvRowStride = uPlane.bytesPerRow;
    final uvPixelStride = uPlane.bytesPerPixel ?? 1;

    for (var y = 0; y < height; y++) {
      final yRowOffset = y * yPlane.bytesPerRow;
      final uvRow = y ~/ 2;
      for (var x = 0; x < width; x++) {
        final yIndex = yRowOffset + x;
        final uvCol = x ~/ 2;
        final uvIndex = uvRow * uvRowStride + uvCol * uvPixelStride;

        final yValue = yPlane.bytes[yIndex];
        final uValue = uPlane.bytes[uvIndex];
        final vValue = vPlane.bytes[uvIndex];

        final r = (yValue + 1.402 * (vValue - 128)).clamp(0, 255).toInt();
        final g = (yValue - 0.344136 * (uValue - 128) - 0.714136 * (vValue - 128))
            .clamp(0, 255)
            .toInt();
        final b = (yValue + 1.772 * (uValue - 128)).clamp(0, 255).toInt();

        out.setPixelRgb(x, y, r, g, b);
      }
    }

    return out;
  }
}
