import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import '../domain/id_image_quality.dart';
import 'id_bitmap_luma.dart';
import 'id_document_evidence_reader.dart';

/// Decodes a captured ID photo and runs document-presence + quality checks.
class IdImageQualityAnalyzer {
  IdImageQualityAnalyzer({IdDocumentEvidenceReader? evidenceReader})
    : _evidenceReader = evidenceReader ?? IdDocumentEvidenceReader();

  final IdDocumentEvidenceReader _evidenceReader;

  Future<IdQualityResult> analyze(
    Uint8List? bytes, {
    bool requireIdPhoto = false,
  }) async {
    if (bytes == null || bytes.isEmpty) {
      return IdQualityResult.fail(IdQualityIssue.missing);
    }

    final sampled = await IdBitmapLuma.decode(
      bytes,
      maxWidth: IdBitmapLuma.analyzeMaxWidth,
    );
    if (sampled == null) {
      return IdQualityResult.fail(IdQualityIssue.notId);
    }

    try {
      if (sampled.nativeWidth < IdImageMetrics.minShortSide ||
          sampled.nativeHeight < IdImageMetrics.minShortSide) {
        return IdQualityResult.fail(IdQualityIssue.tooSmall);
      }

      var evidence = const DocumentEvidence.unknown();
      final window = IdImageMetrics.documentWindow(
        sampled.luma,
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
      if (mean >= IdImageMetrics.minBrightness) {
        try {
          final overlayBytes = await _overlayBytes(bytes, sampled, window);
          if (overlayBytes.isNotEmpty) {
            evidence = await _evidenceReader.inspect(
              overlayBytes,
              overlay: OverlayNormRect.full,
            );
          }
        } catch (_) {
          evidence = const DocumentEvidence.unknown();
        }
      }

      final quality = IdImageMetrics.evaluate(
        luma: sampled.luma,
        width: sampled.width,
        height: sampled.height,
        sourceWidth: sampled.nativeWidth,
        sourceHeight: sampled.nativeHeight,
        evidence: evidence,
        requireIdPhoto: requireIdPhoto,
      );
      if (kDebugMode) {
        debugPrint(
          'ID_CAPTURE jpeg id=${quality.passed ? 'yes' : 'no'} '
          'issue=${quality.issue?.name ?? 'none'} '
          'ocrOn=${evidence.available} '
          'ocrChars=${evidence.alphanumericChars} '
          'face=${evidence.faceCoverage.toStringAsFixed(2)} '
          'debug=${quality.debug ?? ''}',
        );
      }
      return quality;
    } catch (_) {
      return IdQualityResult.fail(IdQualityIssue.notId);
    } finally {
      sampled.image.dispose();
    }
  }

  Future<Uint8List> _overlayBytes(
    Uint8List original,
    DecodedIdBitmap sampled,
    IdCardWindow window,
  ) async {
    if (window.x0 == 0 &&
        window.y0 == 0 &&
        window.width == sampled.width &&
        window.height == sampled.height) {
      return original;
    }
    return await _overlayPng(sampled.image, window) ?? Uint8List(0);
  }

  Future<Uint8List?> _overlayPng(ui.Image image, IdCardWindow window) async {
    if (window.width < 8 || window.height < 8) return null;
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
      ui.Rect.fromLTWH(0, 0, window.width.toDouble(), window.height.toDouble()),
      ui.Paint(),
    );
    final picture = recorder.endRecording();
    final cropped = await picture.toImage(window.width, window.height);
    picture.dispose();
    final png = await cropped.toByteData(format: ui.ImageByteFormat.png);
    cropped.dispose();
    if (png == null) return null;
    return Uint8List.fromList(
      png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes),
    );
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
