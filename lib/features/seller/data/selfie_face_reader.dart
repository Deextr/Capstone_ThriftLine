import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import '../domain/selfie_image_quality.dart';

/// Detects faces in a still selfie. Implementations must not log image bytes.
abstract class SelfieFaceReader {
  Future<List<SelfieDetectedFace>> detect({
    required Uint8List bytes,
    String? filePath,
  });
}

/// On-device ML Kit pass over the captured file (or a short-lived temp copy).
class MlKitSelfieFaceReader implements SelfieFaceReader {
  @override
  Future<List<SelfieDetectedFace>> detect({
    required Uint8List bytes,
    String? filePath,
  }) async {
    if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) {
      return const [];
    }
    if (bytes.isEmpty && (filePath == null || filePath.isEmpty)) {
      return const [];
    }

    FaceDetector? detector;
    File? ownedTemp;
    try {
      final path = await _resolvePath(bytes, filePath);
      if (path == null) return const [];
      if (filePath == null || filePath.isEmpty) {
        ownedTemp = File(path);
      }

      detector = FaceDetector(
        options: FaceDetectorOptions(
          enableLandmarks: true,
          performanceMode: FaceDetectorMode.accurate,
          minFaceSize: 0.05,
        ),
      );

      final input = InputImage.fromFilePath(path);
      final detected = await detector.processImage(input);
      final size = await _imageSize(input, bytes);
      if (size == null) return const [];

      return [
        for (final face in detected)
          _fromFace(face, imageWidth: size.width, imageHeight: size.height),
      ];
    } catch (_) {
      return const [];
    } finally {
      await detector?.close();
      if (ownedTemp != null) {
        try {
          if (await ownedTemp.exists()) await ownedTemp.delete();
        } catch (_) {}
      }
    }
  }

  Future<String?> _resolvePath(Uint8List bytes, String? filePath) async {
    if (filePath != null && filePath.isNotEmpty) {
      final existing = File(filePath);
      if (await existing.exists()) return filePath;
    }
    if (bytes.isEmpty) return null;
    final file = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}'
      'tl_selfie_${DateTime.now().microsecondsSinceEpoch}.jpg',
    );
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  Future<({double width, double height})?> _imageSize(
    InputImage input,
    Uint8List bytes,
  ) async {
    final meta = input.metadata?.size;
    if (meta != null && meta.width > 0 && meta.height > 0) {
      return (width: meta.width, height: meta.height);
    }
    if (bytes.isEmpty) return null;
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final width = frame.image.width.toDouble();
      final height = frame.image.height.toDouble();
      frame.image.dispose();
      if (width > 0 && height > 0) return (width: width, height: height);
    } catch (_) {}
    return null;
  }

  SelfieDetectedFace _fromFace(
    Face face, {
    required double imageWidth,
    required double imageHeight,
  }) {
    final box = face.boundingBox;
    return SelfieDetectedFace(
      left: box.left / imageWidth,
      top: box.top / imageHeight,
      right: box.right / imageWidth,
      bottom: box.bottom / imageHeight,
      looksOccluded: _looksOccluded(face),
    );
  }

  /// Conservative: only reject when landmarks exist but key features are gone.
  /// Glasses still produce eye landmarks, so they are not treated as occlusion.
  bool _looksOccluded(Face face) {
    final landmarks = face.landmarks;
    final present = landmarks.values.where((mark) => mark != null).length;
    if (present == 0) return false;

    final hasLeftEye = landmarks[FaceLandmarkType.leftEye] != null;
    final hasRightEye = landmarks[FaceLandmarkType.rightEye] != null;
    final hasNose = landmarks[FaceLandmarkType.noseBase] != null;
    final hasMouth = landmarks[FaceLandmarkType.bottomMouth] != null ||
        landmarks[FaceLandmarkType.leftMouth] != null ||
        landmarks[FaceLandmarkType.rightMouth] != null;
    final keyCount = [
      hasLeftEye,
      hasRightEye,
      hasNose,
      hasMouth,
    ].where((found) => found).length;
    return keyCount <= 1;
  }
}
