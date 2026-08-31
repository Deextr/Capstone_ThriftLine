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
    this.debug,
  });

  const IdQualityResult.ok({this.debug})
      : passed = true,
        severity = IdQualitySeverity.pass,
        issue = null,
        message = 'Good quality';

  factory IdQualityResult.fail(IdQualityIssue issue, {String? debug}) {
    final warning = issue == IdQualityIssue.slightlySoft;
    return IdQualityResult(
      passed: false,
      severity: warning ? IdQualitySeverity.warning : IdQualitySeverity.fail,
      issue: issue,
      message: messageFor(issue),
      debug: debug,
    );
  }

  final bool passed;
  final IdQualitySeverity severity;
  final IdQualityIssue? issue;
  final String message;

  /// Debug-only metrics. Never shown in release builds.
  final String? debug;

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

/// On-screen ID-1 guide. Must stay in sync with [IdCaptureOverlay].
class IdCaptureGuide {
  static const double cardAspect = 1.586;
  static const double maxHeightFraction = 0.62;
  static const double maxWidthFraction = 0.92;
}

class IdCardWindow {
  const IdCardWindow({
    required this.x0,
    required this.y0,
    required this.width,
    required this.height,
  });

  final int x0;
  final int y0;
  final int width;
  final int height;

  OverlayNormRect toNormalized(int imageWidth, int imageHeight) {
    if (imageWidth <= 0 || imageHeight <= 0) {
      return OverlayNormRect.full;
    }
    return OverlayNormRect(
      left: x0 / imageWidth,
      top: y0 / imageHeight,
      right: (x0 + width) / imageWidth,
      bottom: (y0 + height) / imageHeight,
    );
  }
}

/// Overlay hole in 0–1 image coordinates. Used to ignore laptop UI outside the ID guide.
class OverlayNormRect {
  const OverlayNormRect({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  static const full = OverlayNormRect(left: 0, top: 0, right: 1, bottom: 1);

  final double left;
  final double top;
  final double right;
  final double bottom;

  double get width => _max(0, right - left);
  double get height => _max(0, bottom - top);
  double get area => width * height;

  bool includesBlock({
    required double left,
    required double top,
    required double right,
    required double bottom,
  }) {
    final blockArea = _max(0, right - left) * _max(0, bottom - top);
    if (blockArea <= 0) return false;
    if (intersectionArea(left, top, right, bottom) / blockArea >= 0.5) {
      return true;
    }
    final cx = (left + right) / 2;
    final cy = (top + bottom) / 2;
    return cx >= this.left &&
        cx <= this.right &&
        cy >= this.top &&
        cy <= this.bottom;
  }

  double intersectionArea(double l, double t, double r, double b) {
    final il = l > left ? l : left;
    final it = t > top ? t : top;
    final ir = r < right ? r : right;
    final ib = b < bottom ? b : bottom;
    if (ir <= il || ib <= it) return 0;
    return (ir - il) * (ib - it);
  }

  static double _max(double a, double b) => a > b ? a : b;
}

/// On-device OCR / face hints. Unknown when ML Kit was skipped (tests, web).
class DocumentEvidence {
  const DocumentEvidence({
    required this.available,
    this.alphanumericChars = 0,
    this.blockCount = 0,
    this.faceCoverage = 0,
    this.textMinX,
    this.textMinY,
    this.textMaxX,
    this.textMaxY,
    this.textCoverage = 0,
  });

  const DocumentEvidence.unknown()
      : available = false,
        alphanumericChars = 0,
        blockCount = 0,
        faceCoverage = 0,
        textMinX = null,
        textMinY = null,
        textMaxX = null,
        textMaxY = null,
        textCoverage = 0;

  final bool available;
  final int alphanumericChars;
  final int blockCount;
  final double faceCoverage;

  /// Union of OCR block boxes, normalized 0–1 in the original image.
  final double? textMinX;
  final double? textMinY;
  final double? textMaxX;
  final double? textMaxY;
  final double textCoverage;

  bool get hasTextBounds =>
      textMinX != null &&
      textMinY != null &&
      textMaxX != null &&
      textMaxY != null;
}

/// Evaluates downsampled grayscale luminance (0–255).
class IdImageMetrics {
  static const int minShortSide = 240;
  static const double minBrightness = 42;
  static const double minContrast = 16;
  static const double minOccupancy = 0.28;
  static const double maxOccupancy = 0.97;

  /// Crete-style perceptual blur on the document crop: 0 = sharp, 1 = blurry.
  ///
  /// Real camera JPEGs of glossy IDs commonly land around 0.25–0.45 even when
  /// text is readable, so the fail line is reserved for obviously unreadable
  /// photos. OCR text never skips this check.
  static const double slightlySoftReblur = 0.50;
  static const double blurryReblur = 0.62;

  /// Live preview must fill more of the guide than the post-capture [minOccupancy].
  static const double liveMinOccupancy = 0.40;

  static const int minInWindowChars = 8;
  static const int minInWindowBlocks = 2;
  static const double minFrontFaceCoverage = 0.04;
  static const double maxFrontFaceCoverage = 0.38;
  static const double maxSelfieFaceCoverage = 0.42;
  static const double highOccupancy = 0.85;
  static const double minCardBorderScore = 0.22;
  static const double maxScreenTextCoverage = 0.75;

  static IdQualityResult evaluate({
    required List<int> luma,
    required int width,
    required int height,
    required int sourceWidth,
    required int sourceHeight,
    DocumentEvidence evidence = const DocumentEvidence.unknown(),
    bool requireIdPhoto = false,
  }) {
    if (luma.isEmpty || width < 8 || height < 8) {
      return IdQualityResult.fail(IdQualityIssue.missing);
    }
    if (sourceWidth < minShortSide || sourceHeight < minShortSide) {
      return IdQualityResult.fail(IdQualityIssue.tooSmall);
    }

    final window = centerCardWindow(width, height);
    final crop = extractWindow(luma, width, height, window);
    final cropLuma = crop.luma;
    final cropW = crop.width;
    final cropH = crop.height;

    var sum = 0.0;
    var sumSq = 0.0;
    for (final value in cropLuma) {
      final v = value.toDouble();
      sum += v;
      sumSq += v * v;
    }
    final n = cropLuma.length.toDouble();
    final mean = sum / n;
    final variance = (sumSq / n) - (mean * mean);
    final stddev = variance <= 0 ? 0.0 : _sqrt(variance);

    if (mean < minBrightness) {
      return IdQualityResult.fail(IdQualityIssue.tooDark);
    }

    final geometry = measureGeometry(cropLuma, cropW, cropH, mean);
    final blur = reblurScoreOnRegion(cropLuma, cropW, cropH, geometry);
    final debug =
        'blur=${blur.toStringAsFixed(2)} occ=${geometry.occupancy.toStringAsFixed(2)} '
        'aspect=${geometry.aspectRatio.toStringAsFixed(2)} bands=${geometry.bandCount} '
        'ocr=${evidence.alphanumericChars} blocks=${evidence.blockCount} '
        'ocrOn=${evidence.available} face=${evidence.faceCoverage.toStringAsFixed(2)} '
        'textCov=${evidence.textCoverage.toStringAsFixed(2)} '
        'border=${geometry.borderScore.toStringAsFixed(2)} crop=${cropW}x$cropH';

    // Exists → document-like → size → lighting → blur.
    // A charger must not be reported as "blurry" or "too far".
    if (!_looksLikeDocument(
      geometry,
      evidence,
      requireIdPhoto: requireIdPhoto,
    )) {
      return IdQualityResult.fail(IdQualityIssue.notId, debug: debug);
    }
    if (geometry.occupancy < minOccupancy) {
      return IdQualityResult.fail(IdQualityIssue.tooFar, debug: debug);
    }
    // A featureless blob filling the hole (charger, table) has no card edge
    // and no text-like bands. An ID that fills the guide still has bands or a portrait.
    if (geometry.occupancy >= highOccupancy &&
        geometry.borderScore < minCardBorderScore &&
        geometry.bandCount < 2 &&
        evidence.faceCoverage < minFrontFaceCoverage) {
      return IdQualityResult.fail(IdQualityIssue.notId, debug: debug);
    }
    if (geometry.poorlyFramed) {
      return IdQualityResult.fail(IdQualityIssue.poorFraming, debug: debug);
    }
    if (stddev < minContrast) {
      return IdQualityResult.fail(IdQualityIssue.lowContrast, debug: debug);
    }

    if (blur >= blurryReblur) {
      return IdQualityResult.fail(IdQualityIssue.blurry, debug: debug);
    }
    if (blur >= slightlySoftReblur) {
      return IdQualityResult.fail(IdQualityIssue.slightlySoft, debug: debug);
    }
    return IdQualityResult.ok(debug: debug);
  }

  /// Whether a live camera frame has a card-shaped document filling the guide.
  ///
  /// Does not classify ID type or authenticity. Preview OCR is skipped because
  /// it is too heavy and unreliable at stream rates.
  static bool isLiveAligned({
    required List<int> luma,
    required int width,
    required int height,
  }) {
    if (luma.isEmpty || width < 8 || height < 8) return false;

    final window = centerCardWindow(width, height);
    final crop = extractWindow(luma, width, height, window);
    final stats = _lumaStats(crop.luma);
    if (stats.mean < minBrightness || stats.stddev < minContrast) return false;

    final geometry = measureGeometry(
      crop.luma,
      crop.width,
      crop.height,
      stats.mean,
    );
    if (geometry.occupancy < liveMinOccupancy) return false;
    if (!geometry.cardLikeAspect) return false;
    if (geometry.poorlyFramed) return false;
    if (geometry.bandCount < 2 && geometry.borderScore < 0.22) return false;
    return true;
  }

  /// Copy a Y (or single-channel) plane, stripping row padding.
  static List<int> copyYPlane({
    required List<int> bytes,
    required int width,
    required int height,
    required int bytesPerRow,
  }) {
    if (width < 1 || height < 1) return const [];
    if (bytesPerRow <= width && bytes.length >= width * height) {
      return List<int>.from(bytes.take(width * height));
    }
    final out = List<int>.filled(width * height, 0);
    for (var y = 0; y < height; y++) {
      final src = y * bytesPerRow;
      final dst = y * width;
      for (var x = 0; x < width; x++) {
        final i = src + x;
        if (i >= bytes.length) break;
        out[dst + x] = bytes[i];
      }
    }
    return out;
  }

  /// Convert packed BGRA/RGBA (4 bytes/pixel) to luma.
  static List<int> lumaFromBgra({
    required List<int> bytes,
    required int width,
    required int height,
    required int bytesPerRow,
    bool bgra = true,
  }) {
    final out = List<int>.filled(width * height, 0);
    for (var y = 0; y < height; y++) {
      final srcRow = y * bytesPerRow;
      final dstRow = y * width;
      for (var x = 0; x < width; x++) {
        final o = srcRow + x * 4;
        if (o + 2 >= bytes.length) break;
        final b = bgra ? bytes[o] : bytes[o + 2];
        final g = bytes[o + 1];
        final r = bgra ? bytes[o + 2] : bytes[o];
        out[dstRow + x] = ((0.299 * r) + (0.587 * g) + (0.114 * b)).round();
      }
    }
    return out;
  }

  static ({List<int> luma, int width, int height}) downsample(
    List<int> luma,
    int width,
    int height, {
    int maxWidth = 320,
  }) {
    if (width <= maxWidth || width < 8 || height < 8) {
      return (luma: luma, width: width, height: height);
    }
    final nw = maxWidth;
    final nh = ((height * nw) / width).round().clamp(8, height);
    final out = List<int>.filled(nw * nh, 0);
    for (var y = 0; y < nh; y++) {
      final srcY = (y * height) ~/ nh;
      final srcRow = srcY * width;
      final dstRow = y * nw;
      for (var x = 0; x < nw; x++) {
        out[dstRow + x] = luma[srcRow + (x * width) ~/ nw];
      }
    }
    return (luma: out, width: nw, height: nh);
  }

  static ({double mean, double stddev}) _lumaStats(List<int> luma) {
    var sum = 0.0;
    var sumSq = 0.0;
    for (final value in luma) {
      final v = value.toDouble();
      sum += v;
      sumSq += v * v;
    }
    final n = luma.length.toDouble();
    if (n <= 0) return (mean: 0, stddev: 0);
    final mean = sum / n;
    final variance = (sumSq / n) - (mean * mean);
    return (mean: mean, stddev: variance <= 0 ? 0.0 : _sqrt(variance));
  }

  /// Center ID-1 window matching the on-screen capture overlay.
  static IdCardWindow centerCardWindow(int width, int height) {
    var holeH = (height * IdCaptureGuide.maxHeightFraction).round();
    var holeW = (holeH * IdCaptureGuide.cardAspect).round();
    final maxW = (width * IdCaptureGuide.maxWidthFraction).round();
    if (holeW > maxW) {
      holeW = maxW;
      holeH = (holeW / IdCaptureGuide.cardAspect).round();
    }
    holeW = holeW.clamp(8, width);
    holeH = holeH.clamp(8, height);
    final x0 = ((width - holeW) ~/ 2).clamp(0, width - holeW);
    final y0 = ((height - holeH) ~/ 2).clamp(0, height - holeH);
    return IdCardWindow(x0: x0, y0: y0, width: holeW, height: holeH);
  }

  static ({List<int> luma, int width, int height}) extractWindow(
    List<int> luma,
    int srcWidth,
    int srcHeight,
    IdCardWindow window,
  ) {
    if (window.x0 == 0 &&
        window.y0 == 0 &&
        window.width == srcWidth &&
        window.height == srcHeight) {
      return (luma: luma, width: srcWidth, height: srcHeight);
    }
    final out = List<int>.filled(window.width * window.height, 0);
    for (var y = 0; y < window.height; y++) {
      final srcRow = (window.y0 + y) * srcWidth + window.x0;
      final dstRow = y * window.width;
      for (var x = 0; x < window.width; x++) {
        out[dstRow + x] = luma[srcRow + x];
      }
    }
    return (luma: out, width: window.width, height: window.height);
  }

  static bool _looksLikeDocument(
    IdDocumentGeometry geometry,
    DocumentEvidence evidence, {
    required bool requireIdPhoto,
  }) {
    if (evidence.available && evidence.faceCoverage > maxSelfieFaceCoverage) {
      return false;
    }

    if (!evidence.available) {
      return geometry.bandCount >= 3;
    }

    if (evidence.textCoverage >= maxScreenTextCoverage) return false;

    final hasText = evidence.alphanumericChars >= minInWindowChars &&
        evidence.blockCount >= minInWindowBlocks;
    final hasPortrait = evidence.faceCoverage >= minFrontFaceCoverage &&
        evidence.faceCoverage <= maxFrontFaceCoverage;

    if (hasText) {
      if (!geometry.cardLikeAspect) return false;
      if (requireIdPhoto) {
        // ML Kit often misses the printed photo on a real ID. Accept a
        // detected portrait, or document-like text bands plus in-window text.
        return hasPortrait || geometry.bandCount >= 3;
      }
      return geometry.bandCount >= 2 || hasPortrait;
    }

    // OCR ran but found no text in the overlay crop (glare, or a charger).
    // Fall back to geometry so a real ID can still pass.
    return geometry.bandCount >= 3;
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
    final pad = (width < height ? width : height) * 0.08;
    return IdDocumentGeometry(
      occupancy: occupancy,
      aspectRatio: aspect,
      bandCount: bands,
      borderScore: borderScore,
      minX: minX,
      minY: minY,
      maxX: maxX,
      maxY: maxY,
      touchesLeft: minX <= pad,
      touchesRight: maxX >= width - 1 - pad,
      touchesTop: minY <= pad,
      touchesBottom: maxY >= height - 1 - pad,
    );
  }

  /// Blur on the detected document crop so a sharp ID on a soft table is not
  /// penalized by background defocus.
  static double reblurScoreOnRegion(
    List<int> luma,
    int width,
    int height,
    IdDocumentGeometry geometry,
  ) {
    if (geometry.maxX <= geometry.minX || geometry.maxY <= geometry.minY) {
      return reblurScore(luma, width, height);
    }
    const inset = 2;
    final x0 = _clamp(geometry.minX + inset, 0, width - 3);
    final y0 = _clamp(geometry.minY + inset, 0, height - 3);
    final x1 = _clamp(geometry.maxX - inset, x0 + 2, width - 1);
    final y1 = _clamp(geometry.maxY - inset, y0 + 2, height - 1);
    final cropW = x1 - x0 + 1;
    final cropH = y1 - y0 + 1;
    if (cropW < 12 || cropH < 12) {
      return reblurScore(luma, width, height);
    }
    final crop = List<int>.filled(cropW * cropH, 0);
    for (var y = 0; y < cropH; y++) {
      for (var x = 0; x < cropW; x++) {
        crop[y * cropW + x] = luma[(y0 + y) * width + (x0 + x)];
      }
    }
    return reblurScore(crop, cropW, cropH);
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
    this.minX = 0,
    this.minY = 0,
    this.maxX = 0,
    this.maxY = 0,
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
        minX = 0,
        minY = 0,
        maxX = 0,
        maxY = 0,
        touchesLeft = false,
        touchesRight = false,
        touchesTop = false,
        touchesBottom = false;

  final double occupancy;
  final double aspectRatio;
  final int bandCount;
  final double borderScore;
  final int minX;
  final int minY;
  final int maxX;
  final int maxY;
  final bool touchesLeft;
  final bool touchesRight;
  final bool touchesTop;
  final bool touchesBottom;

  bool get cardLikeAspect =>
      (aspectRatio >= 1.18 && aspectRatio <= 1.98) ||
      (aspectRatio >= 0.50 && aspectRatio <= 0.85);

  /// Filling the on-screen ID guide is expected. A bbox that covers most of
  /// the overlay crop is not treated as a cropped card. A mid-size card that
  /// is clipped on only one side of an axis is hanging out of the frame.
  bool get poorlyFramed {
    if (occupancy < IdImageMetrics.minOccupancy) return false;
    if (occupancy >= 0.75) return false;
    return (touchesLeft != touchesRight) || (touchesTop != touchesBottom);
  }
}
