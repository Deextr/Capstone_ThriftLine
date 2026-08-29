/// Practical ID-presence + photo-quality gate for seller ID captures.
///
/// These checks reject obviously unusable photos. They do not prove that an
/// ID is authentic, government-issued, or belongs to the applicant.
enum IdQualityIssue {
  missing,
  tooSmall,
  notId,
  tooFar,
  poorFraming,
  tooDark,
  lowContrast,
  slightlySoft,
  blurry,
}

enum IdQualitySeverity { pass, warning, fail }

class IdQualityResult {
  const IdQualityResult({
    required this.passed,
    required this.severity,
    this.issue,
    required this.message,
  });

  const IdQualityResult.ok()
      : passed = true,
        severity = IdQualitySeverity.pass,
        issue = null,
        message = 'Good quality';

  factory IdQualityResult.fail(IdQualityIssue issue) {
    final warning = issue == IdQualityIssue.slightlySoft;
    return IdQualityResult(
      passed: false,
      severity: warning ? IdQualitySeverity.warning : IdQualitySeverity.fail,
      issue: issue,
      message: messageFor(issue),
    );
  }

  final bool passed;
  final IdQualitySeverity severity;
  final IdQualityIssue? issue;
  final String message;

  static String messageFor(IdQualityIssue issue) => switch (issue) {
        IdQualityIssue.missing => 'Both front and back photos are required.',
        IdQualityIssue.tooSmall =>
          'Photo resolution is too low. Please retake the photo.',
        IdQualityIssue.notId =>
          'No ID detected. Please place your ID inside the frame and try again.',
        IdQualityIssue.tooFar =>
          'ID is too far away. Move closer and make sure the ID fills the frame.',
        IdQualityIssue.poorFraming =>
          'Make sure the entire ID is visible inside the frame.',
        IdQualityIssue.tooDark =>
          'Image is too dark. Please move to a well-lit area and retake the photo.',
        IdQualityIssue.lowContrast =>
          'Image is too dark. Please move to a well-lit area and retake the photo.',
        IdQualityIssue.slightlySoft =>
          'Image may be blurry. Please hold your phone steady and retake the photo.',
        IdQualityIssue.blurry =>
          'Image too blurry. Please hold your phone steady and retake the photo.',
      };
}

class IdCapturePair {
  const IdCapturePair({this.front, this.back});

  final IdQualityResult? front;
  final IdQualityResult? back;

  bool get canProceed =>
      front != null &&
      back != null &&
      front!.passed &&
      back!.passed;

  IdQualityIssue? get blockingIssue {
    if (front == null || back == null) return IdQualityIssue.missing;
    if (!front!.passed) return front!.issue;
    if (!back!.passed) return back!.issue;
    return null;
  }
}

/// On-device OCR / face hints. Unknown when ML Kit was skipped (tests, web).
class DocumentEvidence {
  const DocumentEvidence({
    required this.available,
    this.alphanumericChars = 0,
    this.blockCount = 0,
    this.faceCoverage = 0,
  });

  const DocumentEvidence.unknown()
      : available = false,
        alphanumericChars = 0,
        blockCount = 0,
        faceCoverage = 0;

  final bool available;
  final int alphanumericChars;
  final int blockCount;
  final double faceCoverage;
}

/// Evaluates downsampled grayscale luminance (0–255).
class IdImageMetrics {
  static const int minShortSide = 240;
  static const double minBrightness = 42;
  static const double minContrast = 16;
  static const double minOccupancy = 0.28;
  static const double maxOccupancy = 0.97;

  /// Crete-style perceptual blur: 0 = sharp, 1 = fully blurry.
  static const double slightlySoftReblur = 0.28;
  static const double blurryReblur = 0.52;

  static IdQualityResult evaluate({
    required List<int> luma,
    required int width,
    required int height,
    required int sourceWidth,
    required int sourceHeight,
    DocumentEvidence evidence = const DocumentEvidence.unknown(),
  }) {
    if (luma.isEmpty || width < 8 || height < 8) {
      return IdQualityResult.fail(IdQualityIssue.missing);
    }
    if (sourceWidth < minShortSide || sourceHeight < minShortSide) {
      return IdQualityResult.fail(IdQualityIssue.tooSmall);
    }

    var sum = 0.0;
    var sumSq = 0.0;
    for (final value in luma) {
      final v = value.toDouble();
      sum += v;
      sumSq += v * v;
    }
    final n = luma.length.toDouble();
    final mean = sum / n;
    final variance = (sumSq / n) - (mean * mean);
    final stddev = variance <= 0 ? 0.0 : _sqrt(variance);

    if (mean < minBrightness) {
      return IdQualityResult.fail(IdQualityIssue.tooDark);
    }
    if (stddev < minContrast) {
      return IdQualityResult.fail(IdQualityIssue.lowContrast);
    }

    final geometry = measureGeometry(luma, width, height, mean);

    if (geometry.occupancy < minOccupancy) {
      return IdQualityResult.fail(IdQualityIssue.tooFar);
    }

    final blur = reblurScore(luma, width, height);
    final tenengrad = tenengradMean(luma, width, height);
    final potentialCard = geometry.cardLikeAspect;

    // Card-shaped regions: prefer a blur message over "no ID" so a defocused
    // ID is not mislabeled as a random object.
    if (potentialCard) {
      if (tenengrad < 12 || blur >= blurryReblur) {
        return IdQualityResult.fail(IdQualityIssue.blurry);
      }
      if (blur >= slightlySoftReblur) {
        return IdQualityResult.fail(IdQualityIssue.slightlySoft);
      }
      if (!_looksLikeDocument(geometry, evidence)) {
        return IdQualityResult.fail(IdQualityIssue.notId);
      }
      if (geometry.poorlyFramed) {
        return IdQualityResult.fail(IdQualityIssue.poorFraming);
      }
      return const IdQualityResult.ok();
    }

    if (!_looksLikeDocument(geometry, evidence)) {
      return IdQualityResult.fail(IdQualityIssue.notId);
    }
    if (geometry.poorlyFramed) {
      return IdQualityResult.fail(IdQualityIssue.poorFraming);
    }
    if (tenengrad < 12 || blur >= blurryReblur) {
      return IdQualityResult.fail(IdQualityIssue.blurry);
    }
    if (blur >= slightlySoftReblur) {
      return IdQualityResult.fail(IdQualityIssue.slightlySoft);
    }

    return const IdQualityResult.ok();
  }

  static bool _looksLikeDocument(
    IdDocumentGeometry geometry,
    DocumentEvidence evidence,
  ) {
    final cardShape = geometry.cardLikeAspect && geometry.occupancy >= minOccupancy;
    final textLike = geometry.bandCount >= 3;
    final ocr =
        evidence.available && (evidence.alphanumericChars >= 8 || evidence.blockCount >= 2);
    final strongOcr = evidence.available && evidence.alphanumericChars >= 18;
    final selfie = evidence.available &&
        evidence.faceCoverage > 0.42 &&
        evidence.alphanumericChars < 8 &&
        !cardShape;

    if (selfie) return false;
    if (strongOcr && geometry.occupancy >= 0.22) return true;
    if (cardShape && (textLike || ocr || geometry.borderScore >= 0.40)) {
      return true;
    }
    if (ocr && geometry.occupancy >= 0.30 && geometry.cardLikeAspect) {
      return true;
    }
    return false;
  }

  static IdDocumentGeometry measureGeometry(
    List<int> luma,
    int width,
    int height,
    double mean,
  ) {
    final border = _borderMedian(luma, width, height);
    var minX = width;
    var minY = height;
    var maxX = -1;
    var maxY = -1;
    var hits = 0;

    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final value = luma[y * width + x];
        final edge = x > 0 && (value - luma[y * width + x - 1]).abs() > 18;
        if ((value - border).abs() < 20 && !edge) continue;
        hits++;
        if (x < minX) minX = x;
        if (y < minY) minY = y;
        if (x > maxX) maxX = x;
        if (y > maxY) maxY = y;
      }
    }

    if (hits == 0 || maxX < minX || maxY < minY) {
      return const IdDocumentGeometry.empty();
    }

    final boxW = maxX - minX + 1;
    final boxH = maxY - minY + 1;
    final occupancy = (boxW * boxH) / (width * height);
    final aspect = boxW / boxH;
    final bands = _textBandCount(luma, width, height, minX, maxX, minY, maxY);
    final borderScore = _borderEdgeScore(
      luma,
      width,
      height,
      minX,
      maxX,
      minY,
      maxY,
    );
    const pad = 2;
    return IdDocumentGeometry(
      occupancy: occupancy,
      aspectRatio: aspect,
      bandCount: bands,
      borderScore: borderScore,
      touchesLeft: minX <= pad,
      touchesRight: maxX >= width - 1 - pad,
      touchesTop: minY <= pad,
      touchesBottom: maxY >= height - 1 - pad,
    );
  }

  /// Perceptual blur (Crete et al.): compare edges before vs after a box blur.
  ///
  /// A sharp photo loses a lot of edge energy when re-blurred (low score).
  /// An already-blurry photo barely changes (high score).
  static double reblurScore(List<int> luma, int width, int height) {
    final blurred = boxBlur(luma, width, height, 2);
    final horizontal = _reblurAxis(
      luma,
      blurred,
      width,
      height,
      horizontal: true,
    );
    final vertical = _reblurAxis(
      luma,
      blurred,
      width,
      height,
      horizontal: false,
    );
    return horizontal > vertical ? horizontal : vertical;
  }

  static double tenengradMean(List<int> luma, int width, int height) {
    var sum = 0.0;
    var count = 0;
    for (var y = 1; y < height - 1; y++) {
      for (var x = 1; x < width - 1; x++) {
        final gx = luma[y * width + x + 1] - luma[y * width + x - 1];
        final gy = luma[(y + 1) * width + x] - luma[(y - 1) * width + x];
        sum += gx * gx + gy * gy;
        count++;
      }
    }
    return count == 0 ? 0 : sum / count;
  }

  static List<int> boxBlur(List<int> src, int width, int height, int radius) {
    if (radius < 1) return List<int>.from(src);
    final tmp = List<int>.filled(src.length, 0);
    final out = List<int>.filled(src.length, 0);
    final span = radius * 2 + 1;

    for (var y = 0; y < height; y++) {
      var acc = 0;
      for (var x = -radius; x <= radius; x++) {
        acc += src[y * width + _clamp(x, 0, width - 1)];
      }
      for (var x = 0; x < width; x++) {
        tmp[y * width + x] = acc ~/ span;
        final leave = src[y * width + _clamp(x - radius, 0, width - 1)];
        final enter = src[y * width + _clamp(x + radius + 1, 0, width - 1)];
        acc += enter - leave;
      }
    }
    for (var x = 0; x < width; x++) {
      var acc = 0;
      for (var y = -radius; y <= radius; y++) {
        acc += tmp[_clamp(y, 0, height - 1) * width + x];
      }
      for (var y = 0; y < height; y++) {
        out[y * width + x] = acc ~/ span;
        final leave = tmp[_clamp(y - radius, 0, height - 1) * width + x];
        final enter = tmp[_clamp(y + radius + 1, 0, height - 1) * width + x];
        acc += enter - leave;
      }
    }
    return out;
  }

  static double _reblurAxis(
    List<int> original,
    List<int> blurred,
    int width,
    int height, {
    required bool horizontal,
  }) {
    var sumOrig = 0.0;
    var sumKeep = 0.0;
    if (horizontal) {
      for (var y = 0; y < height; y++) {
        for (var x = 1; x < width; x++) {
          final dF = (original[y * width + x] - original[y * width + x - 1]).abs();
          final dB = (blurred[y * width + x] - blurred[y * width + x - 1]).abs();
          sumOrig += dF;
          sumKeep += dF > dB ? dF - dB : 0;
        }
      }
    } else {
      for (var y = 1; y < height; y++) {
        for (var x = 0; x < width; x++) {
          final dF = (original[y * width + x] - original[(y - 1) * width + x]).abs();
          final dB = (blurred[y * width + x] - blurred[(y - 1) * width + x]).abs();
          sumOrig += dF;
          sumKeep += dF > dB ? dF - dB : 0;
        }
      }
    }
    if (sumOrig < 1) return 1;
    return 1 - (sumKeep / sumOrig);
  }

  static int _borderMedian(List<int> luma, int width, int height) {
    final samples = <int>[];
    for (var x = 0; x < width; x++) {
      samples.add(luma[x]);
      samples.add(luma[(height - 1) * width + x]);
    }
    for (var y = 1; y < height - 1; y++) {
      samples.add(luma[y * width]);
      samples.add(luma[y * width + width - 1]);
    }
    samples.sort();
    return samples[samples.length ~/ 2];
  }

  static int _textBandCount(
    List<int> luma,
    int width,
    int height,
    int minX,
    int maxX,
    int minY,
    int maxY,
  ) {
    final rowH = maxY - minY + 1;
    final rowW = maxX - minX + 1;
    if (rowH < 12 || rowW < 12) return 0;

    final energy = List<double>.filled(rowH, 0);
    for (var y = minY; y <= maxY; y++) {
      var row = 0.0;
      for (var x = minX + 1; x <= maxX; x++) {
        row += (luma[y * width + x] - luma[y * width + x - 1]).abs();
      }
      energy[y - minY] = row / rowW;
    }

    var mean = 0.0;
    for (final e in energy) {
      mean += e;
    }
    mean /= energy.length;

    var runs = 0;
    var inRun = false;
    var runLen = 0;
    final threshold = mean * 1.15;
    final minRun = 1;
    final maxRun = (rowH * 0.18).clamp(2, 12).round();
    for (final e in energy) {
      if (e >= threshold) {
        inRun = true;
        runLen++;
      } else if (inRun) {
        if (runLen >= minRun && runLen <= maxRun) runs++;
        inRun = false;
        runLen = 0;
      }
    }
    if (inRun && runLen >= minRun && runLen <= maxRun) runs++;
    return runs;
  }

  static double _borderEdgeScore(
    List<int> luma,
    int width,
    int height,
    int minX,
    int maxX,
    int minY,
    int maxY,
  ) {
    var strong = 0;
    var total = 0;
    void sample(int x, int y, int dx, int dy) {
      final a = luma[y * width + x];
      final nx = _clamp(x + dx, 0, width - 1);
      final ny = _clamp(y + dy, 0, height - 1);
      final b = luma[ny * width + nx];
      total++;
      if ((a - b).abs() >= 22) strong++;
    }

    for (var x = minX; x <= maxX; x++) {
      sample(x, minY, 0, 1);
      sample(x, maxY, 0, -1);
    }
    for (var y = minY; y <= maxY; y++) {
      sample(minX, y, 1, 0);
      sample(maxX, y, -1, 0);
    }
    return total == 0 ? 0 : strong / total;
  }

  static int _clamp(int value, int min, int max) {
    if (value < min) return min;
    if (value > max) return max;
    return value;
  }

  static double _sqrt(double value) {
    var guess = value / 2;
    if (guess <= 0) return 0;
    for (var i = 0; i < 12; i++) {
      guess = 0.5 * (guess + value / guess);
    }
    return guess;
  }
}

class IdDocumentGeometry {
  const IdDocumentGeometry({
    required this.occupancy,
    required this.aspectRatio,
    required this.bandCount,
    required this.borderScore,
    required this.touchesLeft,
    required this.touchesRight,
    required this.touchesTop,
    required this.touchesBottom,
  });

  const IdDocumentGeometry.empty()
      : occupancy = 0,
        aspectRatio = 0,
        bandCount = 0,
        borderScore = 0,
        touchesLeft = false,
        touchesRight = false,
        touchesTop = false,
        touchesBottom = false;

  final double occupancy;
  final double aspectRatio;
  final int bandCount;
  final double borderScore;
  final bool touchesLeft;
  final bool touchesRight;
  final bool touchesTop;
  final bool touchesBottom;

  bool get cardLikeAspect =>
      (aspectRatio >= 1.18 && aspectRatio <= 1.98) ||
      (aspectRatio >= 0.50 && aspectRatio <= 0.85);

  bool get poorlyFramed {
    final edges = (touchesLeft ? 1 : 0) +
        (touchesRight ? 1 : 0) +
        (touchesTop ? 1 : 0) +
        (touchesBottom ? 1 : 0);
    return occupancy > 0.90 && edges >= 3;
  }
}
