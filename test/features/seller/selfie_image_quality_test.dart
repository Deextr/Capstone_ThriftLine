import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thriftline/features/seller/data/selfie_face_reader.dart';
import 'package:thriftline/features/seller/data/selfie_image_quality_analyzer.dart';
import 'package:thriftline/features/seller/domain/id_image_quality.dart';
import 'package:thriftline/features/seller/domain/liveness_result.dart';
import 'package:thriftline/features/seller/domain/selfie_image_quality.dart';

const _source = 640;
const _w = 160;
const _h = 200;

const _goodFace = SelfieDetectedFace(
  left: 0.22,
  top: 0.18,
  right: 0.78,
  bottom: 0.82,
);

const _completedChallenges = {
  'face': true,
  'lookRight': true,
  'lookLeft': true,
  'blink': true,
};

List<int> _fill(int width, int height, int value) =>
    List<int>.filled(width * height, value);

/// Portrait selfie with high-frequency face detail so reblur can score sharpness.
List<int> _sharpSelfie({int width = _w, int height = _h}) {
  final luma = _fill(width, height, 118);
  const left = 36;
  const right = 124;
  const top = 36;
  const bottom = 164;
  for (var y = top; y <= bottom; y++) {
    for (var x = left; x <= right; x++) {
      luma[y * width + x] = ((x + y) % 2 == 0) ? 210 : 88;
    }
  }
  return luma;
}

List<int> _mix(List<int> a, List<int> b, int aWeight, int bWeight) {
  final out = List<int>.filled(a.length, 0);
  final den = aWeight + bWeight;
  for (var i = 0; i < a.length; i++) {
    out[i] = (a[i] * aWeight + b[i] * bWeight) ~/ den;
  }
  return out;
}

SelfieQualityResult _eval(
  List<int> luma, {
  List<SelfieDetectedFace> faces = const [_goodFace],
  int sourceWidth = _source,
  int sourceHeight = _source,
}) {
  return SelfieImageMetrics.evaluate(
    luma: luma,
    width: _w,
    height: _h,
    sourceWidth: sourceWidth,
    sourceHeight: sourceHeight,
    faces: faces,
  );
}

class _FakeFaceReader implements SelfieFaceReader {
  _FakeFaceReader(this.faces);

  List<SelfieDetectedFace> faces;
  int calls = 0;

  @override
  Future<List<SelfieDetectedFace>> detect({
    required Uint8List bytes,
    String? filePath,
  }) async {
    calls++;
    return faces;
  }
}

Future<Uint8List> _png({
  int width = 320,
  int height = 400,
  int gray = 160,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()..color = Color.fromARGB(255, gray, gray, gray),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SelfieImageMetrics', () {
    test('Test 1 — valid selfie with one clear face passes', () {
      final result = _eval(_sharpSelfie());
      expect(result.passed, isTrue, reason: result.debug);
      expect(result.issue, isNull);
    });

    test('Test 2 — hide face after liveness rejects the captured image', () {
      final quality = _eval(_sharpSelfie(), faces: const []);
      expect(quality.passed, isFalse);
      expect(quality.issue, SelfieQualityIssue.noFace);
      expect(
        SelfieVerificationGate.accepts(
          livenessPassed: true,
          imageQuality: quality,
        ),
        isFalse,
      );
      expect(
        quality.message,
        'No face detected. Please position your face inside the frame.',
      );
    });

    test('Test 3 — random object / no face is a retake', () {
      final result = _eval(_fill(_w, _h, 140), faces: const []);
      expect(result.passed, isFalse);
      expect(result.issue, SelfieQualityIssue.noFace);
    });

    test('Test 4 — blurry face is rejected', () {
      final sharp = _sharpSelfie();
      var blurry = IdImageMetrics.boxBlur(sharp, _w, _h, 3);
      blurry = IdImageMetrics.boxBlur(blurry, _w, _h, 3);
      blurry = IdImageMetrics.boxBlur(blurry, _w, _h, 3);
      final result = _eval(blurry);
      expect(result.passed, isFalse, reason: result.debug);
      expect(result.issue, SelfieQualityIssue.blurry);
      expect(
        result.message,
        'Your face appears blurry. Please hold your phone steady and retake the selfie.',
      );
    });

    test('Test 5 — face too small / too far is rejected', () {
      const tiny = SelfieDetectedFace(
        left: 0.40,
        top: 0.40,
        right: 0.62,
        bottom: 0.58,
      );
      final result = _eval(_sharpSelfie(), faces: const [tiny]);
      expect(result.passed, isFalse);
      expect(result.issue, SelfieQualityIssue.tooSmall);
      expect(result.message, 'Move closer so your face is clearly visible.');
    });

    test('Test 6 — face partially outside the frame is rejected', () {
      const clipped = SelfieDetectedFace(
        left: -0.20,
        top: 0.20,
        right: 0.22,
        bottom: 0.75,
      );
      final result = _eval(_sharpSelfie(), faces: const [clipped]);
      expect(result.passed, isFalse);
      expect(result.issue, SelfieQualityIssue.poorlyFramed);
    });

    test('Test 7 — two faces are rejected', () {
      const left = SelfieDetectedFace(
        left: 0.06,
        top: 0.22,
        right: 0.42,
        bottom: 0.72,
      );
      const right = SelfieDetectedFace(
        left: 0.56,
        top: 0.22,
        right: 0.92,
        bottom: 0.72,
      );
      final result = _eval(_sharpSelfie(), faces: const [left, right]);
      expect(result.passed, isFalse);
      expect(result.issue, SelfieQualityIssue.multipleFaces);
      expect(result.message, 'Only one person should be visible.');
    });

    test('Test 8 — dark selfie is rejected', () {
      final result = _eval(_fill(_w, _h, 22));
      expect(result.passed, isFalse);
      expect(result.issue, SelfieQualityIssue.tooDark);
      expect(
        result.message,
        'The image is too dark. Please move to a better-lit area.',
      );
    });

    test('Test 9 — valid clear selfie passes quality and the full gate', () {
      final quality = _eval(_sharpSelfie());
      expect(quality.passed, isTrue, reason: quality.debug);
      expect(
        SelfieVerificationGate.accepts(
          livenessPassed: true,
          imageQuality: quality,
        ),
        isTrue,
      );
    });

    test('completed liveness never accepts a failed still image', () {
      final hidden = _eval(_fill(_w, _h, 150), faces: const []);
      expect(hidden.passed, isFalse);
      expect(
        SelfieVerificationGate.accepts(
          livenessPassed: true,
          imageQuality: hidden,
        ),
        isFalse,
      );
    });

    test('retake recalculates quality for the new image', () {
      final first = _eval(_fill(_w, _h, 150), faces: const []);
      expect(first.passed, isFalse);
      expect(first.issue, SelfieQualityIssue.noFace);

      final second = _eval(_sharpSelfie());
      expect(second.passed, isTrue, reason: second.debug);
    });

    test('a tiny background face does not count as a second person', () {
      const speck = SelfieDetectedFace(
        left: 0.90,
        top: 0.90,
        right: 0.94,
        bottom: 0.94,
      );
      final result = _eval(_sharpSelfie(), faces: const [_goodFace, speck]);
      expect(result.passed, isTrue, reason: result.debug);
    });

    test('overlapping ML Kit boxes of the same selfie are one person', () {
      const duplicate = SelfieDetectedFace(
        left: 0.28,
        top: 0.24,
        right: 0.74,
        bottom: 0.78,
      );
      final result = _eval(_sharpSelfie(), faces: const [_goodFace, duplicate]);
      expect(result.passed, isTrue, reason: result.debug);
      expect(result.issue, isNull);
      expect(
        SelfieImageMetrics.selectPeople(const [_goodFace, duplicate]).length,
        1,
      );
    });

    test('a nested inner box of the same face is not a second person', () {
      const inner = SelfieDetectedFace(
        left: 0.32,
        top: 0.28,
        right: 0.68,
        bottom: 0.62,
      );
      final result = _eval(_sharpSelfie(), faces: const [_goodFace, inner]);
      expect(result.passed, isTrue, reason: result.debug);
    });

    test('a small false-positive next to a selfie is ignored', () {
      const wallArt = SelfieDetectedFace(
        left: 0.82,
        top: 0.10,
        right: 0.98,
        bottom: 0.32,
      );
      final result = _eval(_sharpSelfie(), faces: const [_goodFace, wallArt]);
      expect(result.passed, isTrue, reason: result.debug);
    });

    test('occluded face is rejected', () {
      const hidden = SelfieDetectedFace(
        left: 0.22,
        top: 0.18,
        right: 0.78,
        bottom: 0.82,
        looksOccluded: true,
      );
      final result = _eval(_sharpSelfie(), faces: const [hidden]);
      expect(result.passed, isFalse);
      expect(result.issue, SelfieQualityIssue.occluded);
    });

    test('user-facing messages omit technical metrics', () {
      for (final issue in SelfieQualityIssue.values) {
        final message = SelfieQualityResult.messageFor(issue);
        expect(message.contains('faceConfidence'), isFalse);
        expect(message.contains('blurScore'), isFalse);
        expect(message.contains('faceArea'), isFalse);
        expect(message.contains('='), isFalse);
      }
    });

    test('low-resolution capture is treated as too far', () {
      final result = _eval(
        _sharpSelfie(),
        sourceWidth: 120,
        sourceHeight: 160,
      );
      expect(result.passed, isFalse);
      expect(result.issue, SelfieQualityIssue.tooSmall);
    });

    test('mild softness still passes when the face is readable', () {
      final sharp = _sharpSelfie();
      final mild = _mix(sharp, IdImageMetrics.boxBlur(sharp, _w, _h, 1), 3, 1);
      final result = _eval(mild);
      expect(result.passed, isTrue, reason: result.debug);
    });
  });

  group('LivenessResult', () {
    test('passed requires both liveness flags and still-image quality', () {
      final result = LivenessResult(
        imageBytes: Uint8List(0),
        fileName: 'liveness.jpg',
        challenges: _completedChallenges,
        imageQualityPassed: false,
      );
      expect(result.livenessPassed, isTrue);
      expect(result.passed, isFalse);
    });

    test('incomplete liveness cannot pass even with a good still image', () {
      final result = LivenessResult(
        imageBytes: Uint8List(0),
        fileName: 'liveness.jpg',
        challenges: {
          'face': true,
          'lookRight': true,
          'lookLeft': true,
          'blink': false,
        },
        imageQualityPassed: true,
      );
      expect(result.livenessPassed, isFalse);
      expect(result.passed, isFalse);
    });

    test('both gates true means the face check passed', () {
      final result = LivenessResult(
        imageBytes: Uint8List.fromList(const [1, 2, 3]),
        fileName: 'liveness.jpg',
        challenges: _completedChallenges,
        imageQualityPassed: true,
      );
      expect(result.passed, isTrue);
    });
  });

  group('SelfieImageQualityAnalyzer', () {
    test('empty bytes fail closed as no face', () async {
      final reader = _FakeFaceReader(const [_goodFace]);
      final analyzer = SelfieImageQualityAnalyzer(faceReader: reader);
      final result = await analyzer.analyze(Uint8List(0));
      expect(result.passed, isFalse);
      expect(result.issue, SelfieQualityIssue.noFace);
      expect(reader.calls, 0);
    });

    test('Test 2 — analyzer rejects a capture with no detected face', () async {
      final reader = _FakeFaceReader(const []);
      final analyzer = SelfieImageQualityAnalyzer(faceReader: reader);
      final result = await analyzer.analyze(await _png());
      expect(reader.calls, 1);
      expect(result.passed, isFalse);
      expect(result.issue, SelfieQualityIssue.noFace);
    });

    test('Test 3 — analyzer rejects a charger / wall capture', () async {
      final reader = _FakeFaceReader(const []);
      final analyzer = SelfieImageQualityAnalyzer(faceReader: reader);
      final result = await analyzer.analyze(await _png(gray: 190));
      expect(result.issue, SelfieQualityIssue.noFace);
    });

    test('Test 7 — analyzer rejects two faces in the still image', () async {
      final reader = _FakeFaceReader(const [
        SelfieDetectedFace(left: 0.06, top: 0.22, right: 0.42, bottom: 0.72),
        SelfieDetectedFace(left: 0.56, top: 0.22, right: 0.92, bottom: 0.72),
      ]);
      final analyzer = SelfieImageQualityAnalyzer(faceReader: reader);
      final result = await analyzer.analyze(await _png());
      expect(result.passed, isFalse);
      expect(result.issue, SelfieQualityIssue.multipleFaces);
    });

    test('Test 8 — analyzer rejects a dark still image with a face', () async {
      final reader = _FakeFaceReader(const [_goodFace]);
      final analyzer = SelfieImageQualityAnalyzer(faceReader: reader);
      final result = await analyzer.analyze(await _png(gray: 20));
      expect(result.passed, isFalse);
      expect(result.issue, SelfieQualityIssue.tooDark);
    });

    test('each analyze call uses the new image faces, not a previous pass', () async {
      final reader = _FakeFaceReader(const [_goodFace]);
      final analyzer = SelfieImageQualityAnalyzer(faceReader: reader);
      final first = await analyzer.analyze(await _png(gray: 20));
      expect(first.passed, isFalse);

      reader.faces = const [];
      final second = await analyzer.analyze(await _png());
      expect(second.passed, isFalse);
      expect(second.issue, SelfieQualityIssue.noFace);
      expect(reader.calls, 2);
    });
  });
}
