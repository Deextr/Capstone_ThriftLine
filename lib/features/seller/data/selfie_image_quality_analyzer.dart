import 'dart:typed_data';
import 'dart:ui' as ui;

import '../domain/selfie_image_quality.dart';
import 'selfie_face_reader.dart';

/// Decodes a captured selfie and runs an independent face + quality check.
class SelfieImageQualityAnalyzer {
  SelfieImageQualityAnalyzer({SelfieFaceReader? faceReader})
    : _faceReader = faceReader ?? MlKitSelfieFaceReader();

  final SelfieFaceReader _faceReader;

  static const int decodeTargetWidth = 720;

  Future<SelfieQualityResult> analyze(
    Uint8List? bytes, {
    String? filePath,
  }) async {
    if (bytes == null || bytes.isEmpty) {
      return SelfieQualityResult.fail(SelfieQualityIssue.noFace);
    }

    try {
      final sampled = await _decodeLuma(bytes);
      if (sampled == null) {
        return SelfieQualityResult.fail(SelfieQualityIssue.noFace);
      }

      final faces = await _faceReader.detect(bytes: bytes, filePath: filePath);

      return SelfieImageMetrics.evaluate(
        luma: sampled.luma,
        width: sampled.width,
        height: sampled.height,
        sourceWidth: sampled.sourceWidth,
        sourceHeight: sampled.sourceHeight,
        faces: faces,
      );
    } catch (_) {
      return SelfieQualityResult.fail(SelfieQualityIssue.noFace);
    }
  }

  Future<_SampledLuma?> _decodeLuma(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(
      bytes,
      targetWidth: decodeTargetWidth,
    );
    final frame = await codec.getNextFrame();
    final image = frame.image;
    final width = image.width;
    final height = image.height;
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data == null) return null;

      final rgba = data.buffer.asUint8List();
      final luma = List<int>.filled(width * height, 0);
      for (var i = 0; i < width * height; i++) {
        final o = i * 4;
        luma[i] =
            ((0.299 * rgba[o]) + (0.587 * rgba[o + 1]) + (0.114 * rgba[o + 2]))
                .round();
      }

      return _SampledLuma(
        luma: luma,
        width: width,
        height: height,
        sourceWidth: width,
        sourceHeight: height,
      );
    } finally {
      image.dispose();
    }
  }
}

class _SampledLuma {
  const _SampledLuma({
    required this.luma,
    required this.width,
    required this.height,
    required this.sourceWidth,
    required this.sourceHeight,
  });

  final List<int> luma;
  final int width;
  final int height;
  final int sourceWidth;
  final int sourceHeight;
}
