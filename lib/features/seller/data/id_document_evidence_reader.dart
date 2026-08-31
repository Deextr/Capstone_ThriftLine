import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../domain/id_image_quality.dart';

/// Reads on-device text and face coverage to support the ID-presence check.
///
/// This is not authenticity verification — it only asks whether the overlay
/// window contains document-like text rather than a random object or a selfie.
class IdDocumentEvidenceReader {
  Future<DocumentEvidence> inspect(
    Uint8List bytes, {
    OverlayNormRect overlay = OverlayNormRect.full,
  }) async {
    if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) {
      return const DocumentEvidence.unknown();
    }

    final file = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}tl_id_${DateTime.now().microsecondsSinceEpoch}.jpg',
    );
    TextRecognizer? recognizer;
    FaceDetector? faces;
    try {
      await file.writeAsBytes(bytes, flush: true);
      final input = InputImage.fromFilePath(file.path);
      recognizer = TextRecognizer(script: TextRecognitionScript.latin);
      faces = FaceDetector(
        options: FaceDetectorOptions(performanceMode: FaceDetectorMode.fast),
      );

      final text = await recognizer.processImage(input);
      final detected = await faces.processImage(input);
      final size = await _imageSize(input, bytes);
      if (size == null) return const DocumentEvidence.unknown();

      final imgW = size.width;
      final imgH = size.height;
      final overlayArea = overlay.area;
      if (overlayArea <= 0) return const DocumentEvidence.unknown();

      var chars = 0;
      var blockCount = 0;
      var minX = double.infinity;
      var minY = double.infinity;
      var maxX = 0.0;
      var maxY = 0.0;

      for (final block in text.blocks) {
        final box = block.boundingBox;
        final left = (box.left / imgW).clamp(0.0, 1.0);
        final top = (box.top / imgH).clamp(0.0, 1.0);
        final right = (box.right / imgW).clamp(0.0, 1.0);
        final bottom = (box.bottom / imgH).clamp(0.0, 1.0);
        if (!overlay.includesBlock(
          left: left,
          top: top,
          right: right,
          bottom: bottom,
        )) {
          continue;
        }
        blockCount++;
        if (left < minX) minX = left;
        if (top < minY) minY = top;
        if (right > maxX) maxX = right;
        if (bottom > maxY) maxY = bottom;
        for (final rune in block.text.runes) {
          final c = String.fromCharCode(rune).toLowerCase();
          final isLetter = c.compareTo('a') >= 0 && c.compareTo('z') <= 0;
          final isDigit = c.compareTo('0') >= 0 && c.compareTo('9') <= 0;
          if (isLetter || isDigit) chars++;
        }
      }

      var faceCoverage = 0.0;
      for (final face in detected) {
        final box = face.boundingBox;
        final left = (box.left / imgW).clamp(0.0, 1.0);
        final top = (box.top / imgH).clamp(0.0, 1.0);
        final right = (box.right / imgW).clamp(0.0, 1.0);
        final bottom = (box.bottom / imgH).clamp(0.0, 1.0);
        final frac = overlay.intersectionArea(left, top, right, bottom) / overlayArea;
        if (frac > faceCoverage) faceCoverage = frac;
      }

      double? textMinX;
      double? textMinY;
      double? textMaxX;
      double? textMaxY;
      var textCoverage = 0.0;
      if (blockCount > 0 && minX.isFinite) {
        textMinX = minX;
        textMinY = minY;
        textMaxX = maxX;
        textMaxY = maxY;
        textCoverage =
            overlay.intersectionArea(minX, minY, maxX, maxY) / overlayArea;
      }

      return DocumentEvidence(
        available: true,
        alphanumericChars: chars,
        blockCount: blockCount,
        faceCoverage: faceCoverage,
        textMinX: textMinX,
        textMinY: textMinY,
        textMaxX: textMaxX,
        textMaxY: textMaxY,
        textCoverage: textCoverage,
      );
    } catch (_) {
      return const DocumentEvidence.unknown();
    } finally {
      await recognizer?.close();
      await faces?.close();
      try {
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }
  }

  Future<({double width, double height})?> _imageSize(
    InputImage input,
    Uint8List bytes,
  ) async {
    final meta = input.metadata?.size;
    if (meta != null && meta.width > 0 && meta.height > 0) {
      return (width: meta.width, height: meta.height);
    }
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
}
