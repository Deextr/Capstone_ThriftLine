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
  IdDocumentEvidenceReader({this.persistDetectors = false});

  /// Keep ML Kit detectors open across live frames. Call [close] on dispose.
  final bool persistDetectors;

  TextRecognizer? _recognizer;
  FaceDetector? _faces;

  Future<void> close() async {
    await _recognizer?.close();
    await _faces?.close();
    _recognizer = null;
    _faces = null;
  }

  Future<DocumentEvidence> inspect(
    Uint8List bytes, {
    OverlayNormRect overlay = OverlayNormRect.full,
  }) async {
    if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) {
      return const DocumentEvidence.unknown();
    }

    final isPng =
        bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47;
    final ext = isPng ? 'png' : 'jpg';
    final file = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}tl_id_${DateTime.now().microsecondsSinceEpoch}.$ext',
    );
    try {
      await file.writeAsBytes(bytes, flush: true);
      final input = InputImage.fromFilePath(file.path);
      // Must await before finally deletes the file. A bare `return future`
      // runs finally first; ML Kit then reads a missing path and we log
      // "ML Kit unavailable" on a still that live OCR already read.
      return await _inspectInput(
        input,
        overlay: overlay,
        detectFaces: true,
        jpegBytes: bytes,
      );
    } catch (error, stack) {
      if (kDebugMode) {
        debugPrint('ID_CAPTURE inspect still failed: $error');
        debugPrint('$stack');
      }
      return const DocumentEvidence.unknown();
    } finally {
      try {
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }
  }

  Future<DocumentEvidence> inspectInputImage(
    InputImage input, {
    OverlayNormRect overlay = OverlayNormRect.full,
    bool detectFaces = true,
  }) async {
    if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) {
      return const DocumentEvidence.unknown();
    }
    try {
      return await _inspectInput(
        input,
        overlay: overlay,
        detectFaces: detectFaces,
      );
    } catch (_) {
      return const DocumentEvidence.unknown();
    }
  }

  Future<DocumentEvidence> _inspectInput(
    InputImage input, {
    required OverlayNormRect overlay,
    required bool detectFaces,
    Uint8List? jpegBytes,
  }) async {
    return _withDetectors((recognizer, faces) async {
      final text = await recognizer.processImage(input);
      final detected = detectFaces
          ? await faces.processImage(input)
          : const <Face>[];
      final size = await _imageSize(input, jpegBytes);
      if (size == null) return const DocumentEvidence.unknown();
      return _measure(
        text: text,
        faces: detected,
        imgW: size.width,
        imgH: size.height,
        overlay: overlay,
      );
    });
  }

  Future<T> _withDetectors<T>(
    Future<T> Function(TextRecognizer recognizer, FaceDetector faces) body,
  ) async {
    final persist = persistDetectors;
    final recognizer = persist
        ? (_recognizer ??= TextRecognizer(script: TextRecognitionScript.latin))
        : TextRecognizer(script: TextRecognitionScript.latin);
    final faces = persist
        ? (_faces ??= FaceDetector(
            options: FaceDetectorOptions(
              performanceMode: FaceDetectorMode.fast,
            ),
          ))
        : FaceDetector(
            options: FaceDetectorOptions(
              performanceMode: FaceDetectorMode.fast,
            ),
          );
    try {
      return await body(recognizer, faces);
    } finally {
      if (!persist) {
        await recognizer.close();
        await faces.close();
      }
    }
  }

  DocumentEvidence _measure({
    required RecognizedText text,
    required List<Face> faces,
    required double imgW,
    required double imgH,
    required OverlayNormRect overlay,
  }) {
    final overlayArea = overlay.area;
    if (overlayArea <= 0) return const DocumentEvidence.unknown();

    var chars = 0;
    var blockCount = 0;
    var minX = double.infinity;
    var minY = double.infinity;
    var maxX = 0.0;
    var maxY = 0.0;
    final textBuffer = StringBuffer();

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
      if (textBuffer.isNotEmpty) textBuffer.write(' ');
      textBuffer.write(block.text);
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
    double? faceCenterX;
    var faceCount = 0;
    for (final face in faces) {
      final box = face.boundingBox;
      final left = (box.left / imgW).clamp(0.0, 1.0);
      final top = (box.top / imgH).clamp(0.0, 1.0);
      final right = (box.right / imgW).clamp(0.0, 1.0);
      final bottom = (box.bottom / imgH).clamp(0.0, 1.0);
      final frac =
          overlay.intersectionArea(left, top, right, bottom) / overlayArea;
      if (frac < 0.01) continue;
      faceCount++;
      if (frac > faceCoverage) {
        faceCoverage = frac;
        faceCenterX = (left + right) / 2;
      }
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
      recognizedText: textBuffer.toString().toLowerCase(),
      faceCenterX: faceCenterX,
      faceCount: faceCount,
    );
  }

  Future<({double width, double height})?> _imageSize(
    InputImage input,
    Uint8List? bytes,
  ) async {
    final meta = input.metadata?.size;
    if (meta != null && meta.width > 0 && meta.height > 0) {
      return (width: meta.width, height: meta.height);
    }
    if (bytes == null || bytes.isEmpty) return null;
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
