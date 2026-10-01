import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import '../domain/id_document_classification.dart';
import '../domain/id_image_quality.dart';
import '../domain/seller_id_type.dart';
import 'id_bitmap_luma.dart';
import 'id_document_evidence_reader.dart';
import 'id_photo_cropper.dart';

/// Decodes a captured ID photo and runs document-presence + quality checks.
class IdImageQualityAnalyzer {
  IdImageQualityAnalyzer({IdDocumentEvidenceReader? evidenceReader})
    : _evidenceReader = evidenceReader ?? IdDocumentEvidenceReader();

  final IdDocumentEvidenceReader _evidenceReader;

  /// Clockwise quarter turns tried for an ID shown on a screen. The eGov app
  /// draws the card sideways, so the phone may be held at any angle.
  static const List<int> screenQuarterTurns = [0, 2, 1, 3];

  /// [analyze], retried at other orientations for [SellerIdType.presentedOnScreen]
  /// when the read fails for a reason a turn can fix. Returns the photo in
  /// the orientation that passed so review and upload stay upright.
  Future<({Uint8List bytes, IdQualityResult quality, int quarterTurns})>
  analyzeOriented(
    Uint8List bytes, {
    required SellerIdType expectedType,
    required IdCaptureSide expectedSide,
    bool requireIdPhoto = false,
    bool sessionTypeConfirmed = false,
    int preferredQuarterTurns = 0,
  }) async {
    final order = expectedType.presentedOnScreen
        ? [
            preferredQuarterTurns % 4,
            ...screenQuarterTurns.where((t) => t != preferredQuarterTurns % 4),
          ]
        : const [0];

    ({Uint8List bytes, IdQualityResult quality, int quarterTurns})? best;
    for (final turns in order) {
      final candidate = await IdPhotoCropper.rotateClockwise(bytes, turns);
      if (candidate == null) continue;
      final quality = await analyze(
        candidate,
        requireIdPhoto: requireIdPhoto,
        expectedType: expectedType,
        expectedSide: expectedSide,
        sessionTypeConfirmed: sessionTypeConfirmed,
      );
      final attempt = (bytes: candidate, quality: quality, quarterTurns: turns);
      if (quality.passed) return attempt;
      if (best == null) {
        best = attempt;
        if (!_turnMayHelp(quality.issue)) break;
      } else if (_confidence(quality.issue) > _confidence(best.quality.issue)) {
        best = attempt;
      }
    }
    return best ??
        (
          bytes: bytes,
          quality: IdQualityResult.fail(IdQualityIssue.uncertain),
          quarterTurns: 0,
        );
  }

  /// Blur, lighting, and framing look the same at every orientation.
  static bool _turnMayHelp(IdQualityIssue? issue) => switch (issue) {
    IdQualityIssue.notId ||
    IdQualityIssue.uncertain ||
    IdQualityIssue.wrongIdType ||
    IdQualityIssue.wrongSide => true,
    _ => false,
  };

  /// A confident read at any orientation beats "not recognized".
  static int _confidence(IdQualityIssue? issue) => switch (issue) {
    IdQualityIssue.wrongSide => 2,
    IdQualityIssue.wrongIdType => 1,
    _ => 0,
  };

  Future<IdQualityResult> analyze(
    Uint8List? bytes, {
    bool requireIdPhoto = false,
    SellerIdType? expectedType,
    IdCaptureSide? expectedSide,
    bool sessionTypeConfirmed = false,
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

      final geometry = IdImageMetrics.measureGeometry(
        crop.luma,
        crop.width,
        crop.height,
        mean,
      );
      final quality = IdImageMetrics.evaluate(
        luma: sampled.luma,
        width: sampled.width,
        height: sampled.height,
        sourceWidth: sampled.nativeWidth,
        sourceHeight: sampled.nativeHeight,
        evidence: evidence,
        requireIdPhoto: requireIdPhoto,
        allowDisplayedDocument: expectedType?.presentedOnScreen ?? false,
      );
      final gated = expectedType == null || expectedSide == null
          ? quality
          : IdDocumentClassifier.apply(
              quality: quality,
              evidence: evidence,
              geometry: geometry,
              expectedType: expectedType,
              expectedSide: expectedSide,
              sessionTypeConfirmed: sessionTypeConfirmed,
            );
      if (kDebugMode) {
        debugPrint(
          'ID_CAPTURE jpeg id=${gated.passed ? 'yes' : 'no'} '
          'issue=${gated.issue?.name ?? 'none'} '
          'expected_type=${expectedType?.storageValue ?? 'none'} '
          'expected_side=${expectedSide?.name ?? 'none'} '
          'ocr_on=${evidence.available} '
          'ocr_chars=${evidence.alphanumericChars} '
          'face=${evidence.faceCoverage.toStringAsFixed(2)}',
        );
      }
      return gated;
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
