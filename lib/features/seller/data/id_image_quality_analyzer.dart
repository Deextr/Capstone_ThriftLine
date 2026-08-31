import 'dart:typed_data';
import 'dart:ui' as ui;

import '../domain/id_image_quality.dart';
import 'id_document_evidence_reader.dart';

/// Decodes a captured ID photo and runs document-presence + quality checks.
class IdImageQualityAnalyzer {
  IdImageQualityAnalyzer({IdDocumentEvidenceReader? evidenceReader})
      : _evidenceReader = evidenceReader ?? IdDocumentEvidenceReader();

  final IdDocumentEvidenceReader _evidenceReader;

  /// Decode short-side target. Large enough to keep text-scale blur, small
  /// enough to stay off the UI thread budget. Must NOT nearest-neighbor
  /// downsample a 1080p JPEG down to ~160px — that was hiding motion blur.
  static const int decodeTargetWidth = 720;

  Future<IdQualityResult> analyze(
    Uint8List? bytes, {
    bool requireIdPhoto = false,
  }) async {
    if (bytes == null || bytes.isEmpty) {
      return IdQualityResult.fail(IdQualityIssue.missing);
    }

    try {
      final sampled = await _decodeLuma(bytes);
      if (sampled == null) {
        return IdQualityResult.fail(IdQualityIssue.missing);
      }

      var evidence = const DocumentEvidence.unknown();
      final window = IdImageMetrics.centerCardWindow(
        sampled.width,
        sampled.height,
      );
      final crop = IdImageMetrics.extractWindow(
        sampled.luma,
        sampled.width,
        sampled.height,
        window,
      );
      final mean = _mean(crop.luma);
      if (mean >= IdImageMetrics.minBrightness &&
          sampled.overlayPng.isNotEmpty) {
        // Run ML Kit on the overlay crop encoded from the same decoded bitmap
        // used for geometry. Mapping overlay fractions onto the raw JPEG is
        // wrong when EXIF rotation differs, and was zeroing OCR on real IDs.
        evidence = await _evidenceReader.inspect(
          sampled.overlayPng,
          overlay: OverlayNormRect.full,
        );
      }

      return IdImageMetrics.evaluate(
        luma: sampled.luma,
        width: sampled.width,
        height: sampled.height,
        sourceWidth: sampled.sourceWidth,
        sourceHeight: sampled.sourceHeight,
        evidence: evidence,
        requireIdPhoto: requireIdPhoto,
      );
    } catch (_) {
      return IdQualityResult.fail(IdQualityIssue.missing);
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

      final window = IdImageMetrics.centerCardWindow(width, height);
      final overlayPng = await _overlayPng(image, window) ?? Uint8List(0);

      return _SampledLuma(
        luma: luma,
        width: width,
        height: height,
        sourceWidth: width,
        sourceHeight: height,
        overlayPng: overlayPng,
      );
    } finally {
      image.dispose();
    }
  }

  Future<Uint8List?> _overlayPng(ui.Image image, IdCardWindow window) async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawImageRect(
      image,
      ui.Rect.fromLTWH(
        window.x0.toDouble(),
        window.y0.toDouble(),
        window.width.toDouble(),
        window.height.toDouble(),
      ),
      ui.Rect.fromLTWH(
        0,
        0,
        window.width.toDouble(),
        window.height.toDouble(),
      ),
      ui.Paint(),
    );
    final picture = recorder.endRecording();
    final cropped = await picture.toImage(window.width, window.height);
    picture.dispose();
    final png = await cropped.toByteData(format: ui.ImageByteFormat.png);
    cropped.dispose();
    return png?.buffer.asUint8List();
  }

  double _mean(List<int> luma) {
    if (luma.isEmpty) return 0;
    var sum = 0;
    for (final v in luma) {
      sum += v;
    }
    return sum / luma.length;
  }
}

class _SampledLuma {
  const _SampledLuma({
    required this.luma,
    required this.width,
    required this.height,
    required this.sourceWidth,
    required this.sourceHeight,
    required this.overlayPng,
  });

  final List<int> luma;
  final int width;
  final int height;
  final int sourceWidth;
  final int sourceHeight;
  final Uint8List overlayPng;
}
