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
  const left = 68;
  const right = 102;
  const top = 42;
  const bottom = 62;
  for (var y = top; y <= bottom; y++) {
    for (var x = left; x <= right; x++) {
      luma[y * _w + x] = 210;
    }
  }
  for (var y = top; y <= bottom; y++) {
    luma[y * _w + left] = 24;
    luma[y * _w + right] = 24;
  }
  for (var x = left; x <= right; x++) {
    luma[top * _w + x] = 24;
    luma[bottom * _w + x] = 24;
  }
  for (final lineY in [45, 49, 53, 57]) {
    for (var x = 74; x < 98; x++) {
      luma[lineY * _w + x] = 30;
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

/// ID painted over a textured table so a full-image bbox would swallow the photo.
List<int> _sharpIdOnTexturedTable() {
  final luma = _fill(_w, _h, 78);
  for (var y = 0; y < _h; y++) {
    for (var x = 0; x < _w; x++) {
      luma[y * _w + x] = 70 + ((x * 3 + y * 5) % 40);
    }
  }
  const left = 28;
  const right = 132;
  const top = 20;
  const bottom = 84;
  for (var y = top; y <= bottom; y++) {
    for (var x = left; x <= right; x++) {
      luma[y * _w + x] = 210;
    }
  }
  for (var y = top; y <= bottom; y++) {
    luma[y * _w + left] = 24;
    luma[y * _w + right] = 24;
  }
  for (var x = left; x <= right; x++) {
    luma[top * _w + x] = 24;
    luma[bottom * _w + x] = 24;
  }
  for (var y = 28; y < 72; y++) {
    for (var x = 36; x < 60; x++) {
      luma[y * _w + x] = 110;
    }
  }
  for (final lineY in [30, 38, 46, 54, 62, 70]) {
    for (var x = 66; x < 124; x++) {
      luma[lineY * _w + x] = 30;
      luma[(lineY + 1) * _w + x] = 30;
    }
  }
  return luma;
}

/// Card filling almost the entire bitmap (would trip the old 2px edge check).
List<int> _fullBleedId() {
  final luma = _fill(_w, _h, 210);
  for (var y = 0; y < _h; y++) {
    luma[y * _w] = 24;
    luma[y * _w + _w - 1] = 24;
  }
  for (var x = 0; x < _w; x++) {
    luma[x] = 24;
    luma[(_h - 1) * _w + x] = 24;
  }
  for (var y = 18; y < 82; y++) {
    for (var x = 10; x < 42; x++) {
      luma[y * _w + x] = 110;
    }
  }
  for (final lineY in [16, 28, 40, 52, 64, 76, 88]) {
    if (lineY + 1 >= _h) continue;
    for (var x = 48; x < 150; x++) {
      luma[lineY * _w + x] = 30;
      luma[(lineY + 1) * _w + x] = 30;
    }
  }
  return luma;
}

/// ID hanging off the left of the overlay crop (partially out of frame).
List<int> _clippedLeftId() {
  final luma = _fill(_w, _h, 78);
  const left = 31;
  const right = 80;
  const top = 22;
  const bottom = 78;
  for (var y = top; y <= bottom; y++) {
    for (var x = left; x <= right; x++) {
      luma[y * _w + x] = 210;
    }
  }
  for (var y = top; y <= bottom; y++) {
    luma[y * _w + left] = 24;
    luma[y * _w + right] = 24;
  }
  for (var x = left; x <= right; x++) {
    luma[top * _w + x] = 24;
    luma[bottom * _w + x] = 24;
  }
  for (var y = 28; y < 70; y++) {
    for (var x = 36; x < 52; x++) {
      luma[y * _w + x] = 110;
    }
  }
  for (final lineY in [30, 38, 46, 54, 62]) {
    for (var x = 54; x < 76; x++) {
      luma[lineY * _w + x] = 30;
      luma[(lineY + 1) * _w + x] = 30;
    }
  }
  return luma;
}

/// Rectangular object with a border but no text lines — like a charger.
List<int> _charger() {
  final luma = _fill(_w, _h, 88);
  const left = 28;
  const right = 132;
  const top = 20;
  const bottom = 84;
  for (var y = top; y <= bottom; y++) {
    for (var x = left; x <= right; x++) {
      luma[y * _w + x] = 170;
    }
  }
  for (var y = top; y <= bottom; y++) {
    luma[y * _w + left] = 28;
    luma[y * _w + right] = 28;
  }
  for (var x = left; x <= right; x++) {
    luma[top * _w + x] = 28;
    luma[bottom * _w + x] = 28;
  }
  return luma;
}

IdQualityResult _eval(
  List<int> luma, {
  DocumentEvidence evidence = const DocumentEvidence.unknown(),
  int sourceWidth = _source,
  int sourceHeight = _source,
  bool requireIdPhoto = false,
}) {
  return IdImageMetrics.evaluate(
    luma: luma,
    width: _w,
    height: _h,
    sourceWidth: sourceWidth,
    sourceHeight: sourceHeight,
    evidence: evidence,
    requireIdPhoto: requireIdPhoto,
  );
}

const _frontIdEvidence = DocumentEvidence(
  available: true,
  alphanumericChars: 24,
  blockCount: 4,
  faceCoverage: 0.12,
  textCoverage: 0.35,
);

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

    test('rejects a flat mid-gray image as not an ID', () {
      expect(_eval(_fill(_w, _h, 128)).issue, IdQualityIssue.notId);
    });

    test('Test 1 — sharp ID passes', () {
      final result = _eval(_sharpId());
      expect(result.passed, isTrue, reason: result.message);
      expect(result.severity, IdQualitySeverity.pass);
    });

    test('Test 2 — slightly soft but still readable ID can pass', () {
      final sharp = _sharpId();
      final blurred = IdImageMetrics.boxBlur(sharp, _w, _h, 1);
      final result = _eval(_mix(sharp, blurred, 3, 1));
      expect(result.passed, isTrue, reason: result.debug ?? result.message);
    });

    test('Test 3 — heavily blurry ID fails as blur, not as cropped', () {
      final heavy = IdImageMetrics.boxBlur(_sharpId(), _w, _h, 2);
      final result = _eval(heavy);
      expect(result.passed, isFalse, reason: result.debug ?? result.message);
      expect(result.issue, isNot(IdQualityIssue.poorFraming));
      expect(result.issue, isNot(IdQualityIssue.notId));
      expect(
        result.issue,
        anyOf(IdQualityIssue.blurry, IdQualityIssue.slightlySoft),
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

    test('Test 5 — blurry random object is rejected', () {
      final blurry = IdImageMetrics.boxBlur(_clutter(), _w, _h, 3);
      final result = _eval(blurry);
      expect(result.passed, isFalse);
      expect(
        result.issue,
        anyOf(IdQualityIssue.notId, IdQualityIssue.lowContrast),
      );
    });

    test('a sharp rectangular charger is not an ID', () {
      final result = _eval(_charger());
      expect(result.issue, IdQualityIssue.notId, reason: result.debug);
      expect(
        result.message,
        'No ID detected. Please place your ID inside the frame and try again.',
      );
    });

    test('a blurry charger is not an ID, not blur-first', () {
      final blurry = IdImageMetrics.boxBlur(_charger(), _w, _h, 3);
      final result = _eval(blurry);
      expect(result.passed, isFalse);
      expect(result.issue, isNot(IdQualityIssue.blurry));
      expect(result.issue, isNot(IdQualityIssue.slightlySoft));
      expect(result.issue, IdQualityIssue.notId, reason: result.debug);
    });

    test('OCR with no text labels a charger as not an ID even if it is sharp', () {
      final result = _eval(
        _charger(),
        evidence: const DocumentEvidence(
          available: true,
          alphanumericChars: 0,
          blockCount: 0,
        ),
      );
      expect(result.issue, IdQualityIssue.notId, reason: result.debug);
    });

    test('OCR with no text labels a blurry charger as not an ID, not blurry', () {
      final blurry = IdImageMetrics.boxBlur(_charger(), _w, _h, 3);
      final result = _eval(
        blurry,
        evidence: const DocumentEvidence(
          available: true,
          alphanumericChars: 0,
          blockCount: 0,
        ),
      );
      expect(result.issue, IdQualityIssue.notId, reason: result.debug);
      expect(result.issue, isNot(IdQualityIssue.blurry));
      expect(result.issue, isNot(IdQualityIssue.slightlySoft));
    });

    test('OCR with no text still allows a banded ID via geometry', () {
      final result = _eval(
        _sharpId(),
        evidence: const DocumentEvidence(
          available: true,
          alphanumericChars: 0,
          blockCount: 0,
        ),
      );
      expect(result.passed, isTrue, reason: result.debug);
    });

    test('readable OCR text does not skip blur on a heavily defocused ID', () {
      var heavy = _sharpId();
      heavy = IdImageMetrics.boxBlur(heavy, _w, _h, 4);
      heavy = IdImageMetrics.boxBlur(heavy, _w, _h, 4);
      final result = _eval(
        heavy,
        evidence: _frontIdEvidence,
        requireIdPhoto: true,
      );
      expect(result.passed, isFalse, reason: result.debug);
      expect(
        result.issue,
        anyOf(IdQualityIssue.blurry, IdQualityIssue.slightlySoft),
      );
    });

    test('an ID clipped on one side of the frame fails as poor framing', () {
      final result = _eval(_clippedLeftId());
      expect(result.passed, isFalse, reason: result.debug ?? result.message);
      expect(result.issue, IdQualityIssue.poorFraming);
      expect(
        result.message,
        'Make sure the entire ID is visible inside the frame.',
      );
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

    test('aligned ID on a textured table is not flagged as cropped', () {
      final result = _eval(_sharpIdOnTexturedTable());
      expect(result.passed, isTrue, reason: result.debug ?? result.message);
      expect(result.issue, isNot(IdQualityIssue.poorFraming));
    });

    test('full-bleed ID that touches the image edges is not flagged as cropped', () {
      final result = _eval(_fullBleedId());
      expect(result.passed, isTrue, reason: result.debug ?? result.message);
      expect(result.issue, isNot(IdQualityIssue.poorFraming));
      expect(
        IdImageMetrics.measureGeometry(
          _fullBleedId(),
          _w,
          _h,
          180,
        ).poorlyFramed,
        isFalse,
      );
    });

    test('center guide on a portrait capture is a landscape ID-1 window', () {
      final window = IdImageMetrics.centerCardWindow(1080, 1920);
      expect(window.width / window.height, closeTo(IdCaptureGuide.cardAspect, 0.05));
      expect(window.width, lessThan(1080));
      expect(window.height, lessThan(1920 * 0.7));
      expect(window.x0, greaterThan(0));
      expect(window.y0, greaterThan(0));
    });

    test('OCR text can confirm a card-shaped region', () {
      final result = _eval(
        _sharpId(),
        evidence: _frontIdEvidence,
        requireIdPhoto: true,
      );
      expect(result.passed, isTrue, reason: result.debug);
    });

    test('charger plus high OCR counts is not an ID', () {
      const leakedLaptopText = DocumentEvidence(
        available: true,
        alphanumericChars: 80,
        blockCount: 10,
        faceCoverage: 0,
        textCoverage: 0.2,
      );
      expect(
        _eval(
          _charger(),
          evidence: leakedLaptopText,
          requireIdPhoto: true,
        ).issue,
        IdQualityIssue.notId,
      );
      expect(
        _eval(
          _charger(),
          evidence: leakedLaptopText,
        ).issue,
        IdQualityIssue.notId,
      );
    });

    test('front without a detected face can still pass a real ID card', () {
      final result = _eval(
        _sharpId(),
        evidence: const DocumentEvidence(
          available: true,
          alphanumericChars: 24,
          blockCount: 4,
          faceCoverage: 0,
          textCoverage: 0.35,
        ),
        requireIdPhoto: true,
      );
      expect(result.passed, isTrue, reason: result.debug);
    });

    test('back without a face can pass when shape and text hold', () {
      final result = _eval(
        _sharpId(),
        evidence: const DocumentEvidence(
          available: true,
          alphanumericChars: 24,
          blockCount: 4,
          faceCoverage: 0,
          textCoverage: 0.35,
        ),
      );
      expect(result.passed, isTrue, reason: result.debug);
    });

    test('a monitor-like text fill is not an ID', () {
      final result = _eval(
        _sharpId(),
        evidence: const DocumentEvidence(
          available: true,
          alphanumericChars: 80,
          blockCount: 12,
          faceCoverage: 0.12,
          textCoverage: 0.92,
        ),
        requireIdPhoto: true,
      );
      expect(result.issue, IdQualityIssue.notId, reason: result.debug);
    });

    test('overlay ignores blocks whose center sits outside the hole', () {
      const hole = OverlayNormRect(left: 0.2, top: 0.2, right: 0.8, bottom: 0.8);
      expect(
        hole.includesBlock(left: 0.0, top: 0.0, right: 0.12, bottom: 0.12),
        isFalse,
      );
      expect(
        hole.includesBlock(left: 0.3, top: 0.3, right: 0.55, bottom: 0.5),
        isTrue,
      );
      expect(
        hole.intersectionArea(0.0, 0.0, 0.1, 0.1) / hole.area,
        0,
      );
    });

    test('live alignment requires a card filling the guide', () {
      expect(
        IdImageMetrics.isLiveAligned(
          luma: _sharpId(),
          width: _w,
          height: _h,
        ),
        isTrue,
      );
      expect(
        IdImageMetrics.isLiveAligned(
          luma: _tinyId(),
          width: _w,
          height: _h,
        ),
        isFalse,
      );
      expect(
        IdImageMetrics.isLiveAligned(
          luma: _fill(_w, _h, 128),
          width: _w,
          height: _h,
        ),
        isFalse,
      );
      expect(
        IdImageMetrics.isLiveAligned(
          luma: _clippedLeftId(),
          width: _w,
          height: _h,
        ),
        isFalse,
      );
    });

    test('Y-plane copy strips row padding', () {
      const width = 8;
      const height = 4;
      const stride = 10;
      final bytes = List<int>.filled(stride * height, 9);
      for (var y = 0; y < height; y++) {
        for (var x = 0; x < width; x++) {
          bytes[y * stride + x] = y * width + x;
        }
      }
      final luma = IdImageMetrics.copyYPlane(
        bytes: bytes,
        width: width,
        height: height,
        bytesPerRow: stride,
      );
      expect(luma.length, width * height);
      expect(luma[0], 0);
      expect(luma[width], width);
      expect(luma.last, width * height - 1);
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
