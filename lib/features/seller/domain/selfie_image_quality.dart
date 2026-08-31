import 'id_image_quality.dart';

/// Practical on-device selfie-presence + quality gate.
///
/// These checks reject a captured photo that does not contain one usable
/// face. They do not prove identity or replace the live challenge.
enum SelfieQualityIssue {
  noFace,
  multipleFaces,
  tooSmall,
  poorlyFramed,
  tooDark,
  blurry,
  occluded,
}

class SelfieQualityResult {
  const SelfieQualityResult({
    required this.passed,
    this.issue,
    required this.message,
    this.debug,
  });

  const SelfieQualityResult.ok({this.debug})
      : passed = true,
        issue = null,
        message = 'Good quality';

  factory SelfieQualityResult.fail(SelfieQualityIssue issue, {String? debug}) {
    return SelfieQualityResult(
      passed: false,
      issue: issue,
      message: messageFor(issue),
      debug: debug,
    );
  }

  final bool passed;
  final SelfieQualityIssue? issue;
  final String message;

  /// Debug-only metrics. Never shown to the user.
  final String? debug;

  static String messageFor(SelfieQualityIssue issue) => switch (issue) {
        SelfieQualityIssue.noFace =>
          'No face detected. Please position your face inside the frame.',
        SelfieQualityIssue.multipleFaces =>
          'Only one person should be visible.',
        SelfieQualityIssue.tooSmall =>
          'Move closer so your face is clearly visible.',
        SelfieQualityIssue.poorlyFramed =>
          'Make sure your whole face is inside the frame.',
        SelfieQualityIssue.tooDark =>
          'The image is too dark. Please move to a better-lit area.',
        SelfieQualityIssue.blurry =>
          'Your face appears blurry. Please hold your phone steady and retake the selfie.',
        SelfieQualityIssue.occluded =>
          'Keep your face uncovered and try again.',
      };
}

/// Normalized face box from an independent still-image detection pass.
class SelfieDetectedFace {
  const SelfieDetectedFace({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
    this.looksOccluded = false,
  });

  /// Bounding box in image coordinates. May extend slightly outside 0–1.
  final double left;
  final double top;
  final double right;
  final double bottom;
  final bool looksOccluded;

  double get width => right - left;
  double get height => bottom - top;

  double get rawCoverage {
    final w = width < 0 ? 0.0 : width;
    final h = height < 0 ? 0.0 : height;
    return w * h;
  }

  double get visibleCoverage {
    final il = _clamp01(left);
    final it = _clamp01(top);
    final ir = _clamp01(right);
    final ib = _clamp01(bottom);
    final w = ir - il;
    final h = ib - it;
    if (w <= 0 || h <= 0) return 0;
    return w * h;
  }

  double get inFrameFraction {
    final raw = rawCoverage;
    if (raw <= 0) return 0;
    final frac = visibleCoverage / raw;
    if (frac < 0) return 0;
    if (frac > 1) return 1;
    return frac;
  }

  double get centerX => (left + right) / 2;
  double get centerY => (top + bottom) / 2;

  double intersectionCoverage(SelfieDetectedFace other) {
    final il = _max(_clamp01(left), _clamp01(other.left));
    final it = _max(_clamp01(top), _clamp01(other.top));
    final ir = _min(_clamp01(right), _clamp01(other.right));
    final ib = _min(_clamp01(bottom), _clamp01(other.bottom));
    final w = ir - il;
    final h = ib - it;
    if (w <= 0 || h <= 0) return 0;
    return w * h;
  }

  double iou(SelfieDetectedFace other) {
    final inter = intersectionCoverage(other);
    final union = visibleCoverage + other.visibleCoverage - inter;
    if (union <= 0) return 0;
    return inter / union;
  }

  /// ML Kit often emits two boxes for the same selfie face.
  bool isSamePersonAs(SelfieDetectedFace other) {
    if (iou(other) >= 0.35) return true;
    final inter = intersectionCoverage(other);
    final smaller =
        visibleCoverage < other.visibleCoverage ? visibleCoverage : other.visibleCoverage;
    return smaller > 0 && inter / smaller >= 0.60;
  }

  static double _clamp01(double value) {
    if (value < 0) return 0;
    if (value > 1) return 1;
    return value;
  }

  static double _min(double a, double b) => a < b ? a : b;
  static double _max(double a, double b) => a > b ? a : b;
}

/// Live challenge flags and still-image quality must both pass.
class SelfieVerificationGate {
  static bool accepts({
    required bool livenessPassed,
    required SelfieQualityResult imageQuality,
  }) =>
      livenessPassed && imageQuality.passed;
}

/// Evaluates a captured selfie from luma + independently detected faces.
class SelfieImageMetrics {
  static const int minShortSide = 240;
  static const double minCountableCoverage = 0.02;
  static const double minFaceCoverage = 0.10;
  static const double minSecondaryFaceCoverage = 0.08;
  static const double minSecondaryRelativeSize = 0.40;
  static const double maxOffCenter = 0.38;
  static const double minInFrameFraction = 0.82;
  static const double minBrightness = 42;
  static const double blurryReblur = 0.62;

  /// Drops ML Kit duplicate boxes and tiny false positives, then keeps
  /// people who are large enough to be a second person in the selfie.
  static List<SelfieDetectedFace> selectPeople(List<SelfieDetectedFace> faces) {
    final countable = faces
        .where((face) => face.visibleCoverage >= minCountableCoverage)
        .toList()
      ..sort((a, b) => b.visibleCoverage.compareTo(a.visibleCoverage));

    if (countable.isEmpty) return const [];

    final unique = <SelfieDetectedFace>[];
    for (final face in countable) {
      if (unique.any(face.isSamePersonAs)) continue;
      unique.add(face);
    }

    final primary = unique.first;
    return [
      primary,
      for (final face in unique.skip(1))
        if (_isRealSecondPerson(primary, face)) face,
    ];
  }

  static bool _isRealSecondPerson(
    SelfieDetectedFace primary,
    SelfieDetectedFace other,
  ) {
    if (other.visibleCoverage < minSecondaryFaceCoverage) return false;
    return other.visibleCoverage >= primary.visibleCoverage * minSecondaryRelativeSize;
  }

  static SelfieQualityResult evaluate({
    required List<int> luma,
    required int width,
    required int height,
    required int sourceWidth,
    required int sourceHeight,
    required List<SelfieDetectedFace> faces,
  }) {
    if (luma.isEmpty || width < 8 || height < 8) {
      return SelfieQualityResult.fail(SelfieQualityIssue.noFace);
    }
    if (sourceWidth < minShortSide || sourceHeight < minShortSide) {
      return SelfieQualityResult.fail(SelfieQualityIssue.tooSmall);
    }

    final people = selectPeople(faces);

    if (people.isEmpty) {
      return SelfieQualityResult.fail(SelfieQualityIssue.noFace);
    }
    if (people.length > 1) {
      return SelfieQualityResult.fail(SelfieQualityIssue.multipleFaces);
    }

    final face = people.first;
    if (face.looksOccluded) {
      return SelfieQualityResult.fail(SelfieQualityIssue.occluded);
    }
    if (face.visibleCoverage < minFaceCoverage) {
      return SelfieQualityResult.fail(SelfieQualityIssue.tooSmall);
    }
    if (face.inFrameFraction < minInFrameFraction) {
      return SelfieQualityResult.fail(SelfieQualityIssue.poorlyFramed);
    }
    if ((face.centerX - 0.5).abs() > maxOffCenter ||
        (face.centerY - 0.5).abs() > maxOffCenter) {
      return SelfieQualityResult.fail(SelfieQualityIssue.poorlyFramed);
    }

    final crop = _faceCrop(luma, width, height, face);
    if (crop.width < 12 || crop.height < 12) {
      return SelfieQualityResult.fail(SelfieQualityIssue.tooSmall);
    }

    final mean = _mean(crop.luma);
    final blur = IdImageMetrics.reblurScore(crop.luma, crop.width, crop.height);
    final debug =
        'blur=${blur.toStringAsFixed(2)} mean=${mean.toStringAsFixed(1)} '
        'cov=${face.visibleCoverage.toStringAsFixed(2)} '
        'inFrame=${face.inFrameFraction.toStringAsFixed(2)} '
        'faces=${people.length} crop=${crop.width}x${crop.height}';

    if (mean < minBrightness) {
      return SelfieQualityResult.fail(SelfieQualityIssue.tooDark, debug: debug);
    }
    if (blur >= blurryReblur) {
      return SelfieQualityResult.fail(SelfieQualityIssue.blurry, debug: debug);
    }
    return SelfieQualityResult.ok(debug: debug);
  }

  static ({List<int> luma, int width, int height}) _faceCrop(
    List<int> luma,
    int width,
    int height,
    SelfieDetectedFace face,
  ) {
    var x0 = (face.left * width).floor();
    var y0 = (face.top * height).floor();
    var x1 = (face.right * width).ceil();
    var y1 = (face.bottom * height).ceil();
    if (x0 < 0) x0 = 0;
    if (y0 < 0) y0 = 0;
    if (x1 > width) x1 = width;
    if (y1 > height) y1 = height;
    if (x1 <= x0) x1 = x0 + 1;
    if (y1 <= y0) y1 = y0 + 1;
    if (x1 > width) x1 = width;
    if (y1 > height) y1 = height;

    final cropW = x1 - x0;
    final cropH = y1 - y0;
    if (cropW < 1 || cropH < 1) {
      return (luma: const <int>[], width: 0, height: 0);
    }

    final out = List<int>.filled(cropW * cropH, 0);
    for (var y = 0; y < cropH; y++) {
      final srcRow = (y0 + y) * width + x0;
      final dstRow = y * cropW;
      for (var x = 0; x < cropW; x++) {
        out[dstRow + x] = luma[srcRow + x];
      }
    }
    return (luma: out, width: cropW, height: cropH);
  }

  static double _mean(List<int> luma) {
    if (luma.isEmpty) return 0;
    var sum = 0;
    for (final value in luma) {
      sum += value;
    }
    return sum / luma.length;
  }
}
