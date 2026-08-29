import 'package:flutter_test/flutter_test.dart';
import 'package:thriftline/features/seller/domain/id_image_quality.dart';

const _source = 640;
const _w = 160;
const _h = 100;

List<int> _fill(int width, int height, int value) =>
    List<int>.filled(width * height, value);

/// Card-shaped region with a photo block and horizontal text-like bands.
List<int> _sharpId({int width = _w, int height = _h}) {
  final luma = _fill(width, height, 78);
  const left = 28;
  const right = 132;
  const top = 20;
  const bottom = 84;
  for (var y = top; y <= bottom; y++) {
    for (var x = left; x <= right; x++) {
      luma[y * width + x] = 210;
    }
  }
  for (var y = top; y <= bottom; y++) {
    luma[y * width + left] = 24;
    luma[y * width + right] = 24;
  }
  for (var x = left; x <= right; x++) {
    luma[top * width + x] = 24;
    luma[bottom * width + x] = 24;
  }
  for (var y = 28; y < 72; y++) {
    for (var x = 36; x < 60; x++) {
      luma[y * width + x] = 110;
    }
  }
  for (final lineY in [30, 38, 46, 54, 62, 70]) {
    for (var x = 66; x < 124; x++) {
      luma[lineY * width + x] = 30;
      luma[(lineY + 1) * width + x] = 30;
    }
  }
  return luma;
}

List<int> _tinyId() {
  final luma = _fill(_w, _h, 96);
  for (var y = 38; y < 62; y++) {
    for (var x = 64; x < 96; x++) {
      luma[y * _w + x] = (x + y).isEven ? 20 : 235;
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

List<int> _clutter() {
  final luma = _fill(_w, _h, 140);
  for (var y = 10; y < 90; y++) {
    for (var x = 40; x < 120; x++) {
      luma[y * _w + x] = ((x * 7 + y * 13) % 3 == 0) ? 48 : 205;
    }
  }
  return luma;
}

IdQualityResult _eval(
  List<int> luma, {
  DocumentEvidence evidence = const DocumentEvidence.unknown(),
  int sourceWidth = _source,
  int sourceHeight = _source,
}) {
  return IdImageMetrics.evaluate(
    luma: luma,
    width: _w,
    height: _h,
    sourceWidth: sourceWidth,
    sourceHeight: sourceHeight,
    evidence: evidence,
  );
}

void main() {
  group('IdImageMetrics', () {
    test('rejects a missing or tiny buffer', () {
      expect(
        IdImageMetrics.evaluate(
          luma: const [],
          width: 0,
          height: 0,
          sourceWidth: _source,
          sourceHeight: _source,
        ).issue,
        IdQualityIssue.missing,
      );
    });

    test('rejects low source resolution', () {
      final result = _eval(_sharpId(), sourceWidth: 120, sourceHeight: 120);
      expect(result.issue, IdQualityIssue.tooSmall);
    });

    test('rejects a very dark image', () {
      final result = _eval(_fill(_w, _h, 10));
      expect(result.issue, IdQualityIssue.tooDark);
      expect(
        result.message,
        'Image is too dark. Please move to a well-lit area and retake the photo.',
      );
    });

    test('rejects a flat mid-gray image as poor contrast', () {
      expect(_eval(_fill(_w, _h, 128)).issue, IdQualityIssue.lowContrast);
    });

    test('Test 1 — sharp ID passes', () {
      final result = _eval(_sharpId());
      expect(result.passed, isTrue, reason: result.message);
      expect(result.severity, IdQualitySeverity.pass);
    });

    test('Test 2 — slightly blurry ID warns and blocks proceed', () {
      final sharp = _sharpId();
      final blurred = IdImageMetrics.boxBlur(sharp, _w, _h, 1);
      final result = _eval(_mix(sharp, blurred, 3, 1));
      expect(result.passed, isFalse, reason: result.message);
      expect(
        result.issue,
        anyOf(IdQualityIssue.slightlySoft, IdQualityIssue.blurry),
      );
      if (result.issue == IdQualityIssue.slightlySoft) {
        expect(result.severity, IdQualitySeverity.warning);
      }
      expect(result.message.toLowerCase(), contains('blurry'));
    });

    test('Test 3 — heavily blurry ID fails', () {
      var heavy = _sharpId();
      heavy = IdImageMetrics.boxBlur(heavy, _w, _h, 4);
      heavy = IdImageMetrics.boxBlur(heavy, _w, _h, 4);
      final result = _eval(heavy);
      expect(result.passed, isFalse);
      expect(result.issue, IdQualityIssue.blurry);
      expect(
        result.message,
        'Image too blurry. Please hold your phone steady and retake the photo.',
      );
    });

    test('Test 4 — sharp random object is not an ID', () {
      final result = _eval(_clutter());
      expect(result.issue, IdQualityIssue.notId);
      expect(
        result.message,
        'No ID detected. Please place your ID inside the frame and try again.',
      );
    });

    test('Test 5 — blurry random object is not an ID', () {
      final blurry = IdImageMetrics.boxBlur(_clutter(), _w, _h, 3);
      final result = _eval(blurry);
      expect(
        result.issue,
        anyOf(IdQualityIssue.notId, IdQualityIssue.blurry, IdQualityIssue.lowContrast),
      );
      expect(result.passed, isFalse);
    });

    test('Test 6 — dark ID is too dark', () {
      expect(_eval(_fill(_w, _h, 18)).issue, IdQualityIssue.tooDark);
    });

    test('Test 7 — small / far ID is rejected', () {
      final result = _eval(_tinyId());
      expect(result.issue, IdQualityIssue.tooFar);
      expect(
        result.message,
        'ID is too far away. Move closer and make sure the ID fills the frame.',
      );
    });

    test('Test 8 — sharp ID filling the frame passes', () {
      expect(_eval(_sharpId()).passed, isTrue);
    });

    test('OCR text can confirm a card-shaped region', () {
      final result = _eval(
        _sharpId(),
        evidence: const DocumentEvidence(
          available: true,
          alphanumericChars: 24,
          blockCount: 4,
        ),
      );
      expect(result.passed, isTrue);
    });

    test('a dominant face with almost no text is not an ID', () {
      final result = _eval(
        _clutter(),
        evidence: const DocumentEvidence(
          available: true,
          alphanumericChars: 2,
          blockCount: 0,
          faceCoverage: 0.55,
        ),
      );
      expect(result.issue, IdQualityIssue.notId);
    });

    test('reblur score rises as the ID is defocused', () {
      final sharp = _sharpId();
      final mild = _mix(sharp, IdImageMetrics.boxBlur(sharp, _w, _h, 1), 3, 1);
      var heavy = sharp;
      heavy = IdImageMetrics.boxBlur(heavy, _w, _h, 4);
      heavy = IdImageMetrics.boxBlur(heavy, _w, _h, 4);
      final s = IdImageMetrics.reblurScore(sharp, _w, _h);
      final m = IdImageMetrics.reblurScore(mild, _w, _h);
      final h = IdImageMetrics.reblurScore(heavy, _w, _h);
      expect(s, lessThan(m));
      expect(m, lessThan(h));
      expect(s, lessThan(IdImageMetrics.slightlySoftReblur));
      expect(h, greaterThan(IdImageMetrics.blurryReblur));
    });

    test('smooth ramp is blurry rather than sharp', () {
      final luma = [
        for (var y = 0; y < _h; y++)
          for (var x = 0; x < _w; x++) 40 + ((x * 180) ~/ (_w - 1)),
      ];
      final result = _eval(luma);
      expect(result.passed, isFalse);
      expect(
        result.issue,
        anyOf(IdQualityIssue.blurry, IdQualityIssue.notId, IdQualityIssue.lowContrast),
      );
    });
  });

  group('IdCapturePair', () {
    test('keeps proceed disabled until both sides exist and pass', () {
      const ok = IdQualityResult.ok();
      final fail = IdQualityResult.fail(IdQualityIssue.blurry);
      final notId = IdQualityResult.fail(IdQualityIssue.notId);

      expect(const IdCapturePair().canProceed, isFalse);
      expect(const IdCapturePair(front: ok).canProceed, isFalse);
      expect(IdCapturePair(front: ok, back: fail).canProceed, isFalse);
      expect(IdCapturePair(front: ok, back: notId).canProceed, isFalse);
      expect(const IdCapturePair(front: ok, back: ok).canProceed, isTrue);
    });
  });
}
