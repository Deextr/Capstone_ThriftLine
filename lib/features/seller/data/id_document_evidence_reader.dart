import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../domain/id_image_quality.dart';

/// Reads on-device text and face coverage to support the ID-presence check.
///
/// This is not authenticity verification — it only asks whether the photo
/// contains document-like text rather than a random object or a selfie.
class IdDocumentEvidenceReader {
  Future<DocumentEvidence> inspect(Uint8List bytes) async {
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

      var chars = 0;
      for (final block in text.blocks) {
        for (final rune in block.text.runes) {
          final c = String.fromCharCode(rune).toLowerCase();
          final isLetter = c.compareTo('a') >= 0 && c.compareTo('z') <= 0;
          final isDigit = c.compareTo('0') >= 0 && c.compareTo('9') <= 0;
          if (isLetter || isDigit) chars++;
        }
      }

      var faceCoverage = 0.0;
      final size = input.metadata?.size;
      final area = (size == null || size.width <= 0 || size.height <= 0)
          ? 0.0
          : size.width * size.height;
      if (area > 0) {
        for (final face in detected) {
          final box = face.boundingBox;
          final frac = (box.width * box.height) / area;
          if (frac > faceCoverage) faceCoverage = frac;
        }
      }

      return DocumentEvidence(
        available: true,
        alphanumericChars: chars,
        blockCount: text.blocks.length,
        faceCoverage: faceCoverage,
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
}
