/// Practical ID-presence + photo-quality gate for seller ID captures.
///
/// These checks reject obviously unusable photos. They do not prove that an
/// ID is authentic, government-issued, or belongs to the applicant.
enum IdQualityIssue {
  missing,
  tooSmall,
  notId,
  notSupportedId,
  tooFar,
  poorFraming,
  tooDark,
  lowContrast,
  slightlySoft,
  blurry,
  glare,
  wrongSide,
  wrongIdType,
  uncertain,
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

  factory IdQualityResult.fail(
    IdQualityIssue issue, {
    String? debug,
    String? message,
  }) {
    final warning = issue == IdQualityIssue.slightlySoft;
    return IdQualityResult(
      passed: false,
      severity: warning ? IdQualitySeverity.warning : IdQualitySeverity.fail,
      issue: issue,
      message: message ?? messageFor(issue),
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
    IdQualityIssue.missing =>
      'This ID photo is missing. Please capture it again.',
    IdQualityIssue.tooSmall =>
      'Photo resolution is too low. Please retake the photo.',
    IdQualityIssue.notId =>
      'No ID detected. Please place your ID inside the frame and try again.',
    IdQualityIssue.notSupportedId =>
      'This is not an ID. Please place your ID inside the frame.',
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
    IdQualityIssue.glare =>
      'Too much glare detected. Please adjust the ID and try again.',
    IdQualityIssue.wrongSide =>
      'Wrong side detected. Please capture the requested side of your ID.',
    IdQualityIssue.wrongIdType =>
      'This photo does not match the selected ID type. Please retake the photo.',
    IdQualityIssue.uncertain =>
      'We couldn\'t verify the ID. Please retake the photo.',
  };
}

class IdCapturePair {
  const IdCapturePair({this.front, this.back});

  final IdQualityResult? front;
  final IdQualityResult? back;

  bool get canProceed =>
      front != null && back != null && front!.passed && back!.passed;

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

  /// How often live preview luma is sampled. Stay well above a frame time.
  static const Duration liveAnalyzeInterval = Duration(milliseconds: 160);

  /// ID must stay valid this long before auto-capture. Tune during device testing.
  static const Duration autoCaptureHold = Duration(milliseconds: 1000);

  /// Occupancy jump that means the ID is still being moved into place.
  static const double motionOccupancyDelta = 0.08;

  /// Below this, live preview is treated as "nothing in the frame".
  static const double liveSearchingOccupancy = 0.12;

  /// How often live OCR/face confirmation may run after luma looks aligned.
  static const Duration liveTextConfirmInterval = Duration(milliseconds: 450);
}

/// Live camera guidance. Not a substitute for post-capture [IdImageMetrics.evaluate].
enum LiveIdStatus {
  searching,
  tooDark,
  tooFar,
  poorlyFramed,
  notId,
  blurry,
  wrongSide,
  aligned,
}

class LiveIdAssessment {
  const LiveIdAssessment({required this.status, this.occupancy = 0});

  const LiveIdAssessment.searching()
    : status = LiveIdStatus.searching,
      occupancy = 0;

  final LiveIdStatus status;
  final double occupancy;

  bool get isAligned => status == LiveIdStatus.aligned;

  /// User-facing copy. Avoids internal metric names.
  String get feedbackMessage => switch (status) {
    LiveIdStatus.searching => 'Place your ID within the frame',
    LiveIdStatus.tooDark => 'Improve the lighting.',
    LiveIdStatus.tooFar => 'Move your ID closer.',
    LiveIdStatus.poorlyFramed => 'Align the edges of your ID within the frame',
    LiveIdStatus.notId =>
      'No ID detected. Please place your ID inside the frame and try again.',
    LiveIdStatus.blurry => 'Make sure the ID is clear and not blurry.',
    LiveIdStatus.wrongSide =>
      'Wrong side detected. Please show the requested side of your ID.',
    LiveIdStatus.aligned => 'ID detected — hold steady',
  };
}

/// Requires several consecutive valid, still frames before auto-capture.
class LiveCaptureStability {
  LiveCaptureStability({
    this.hold = IdCaptureGuide.autoCaptureHold,
    this.motionDelta = IdCaptureGuide.motionOccupancyDelta,
  });

  final Duration hold;
  final double motionDelta;

  DateTime? _alignedSince;
  double? _occupancy;

  bool get isHolding => _alignedSince != null;

  /// Returns true only after [assessment] has stayed aligned and still
  /// for [hold]. A single valid frame is never enough.
  bool observe(LiveIdAssessment assessment, DateTime now) {
    if (!assessment.isAligned) {
      _alignedSince = null;
      _occupancy = assessment.occupancy;
      return false;
    }
    if (_occupancy != null &&
        (assessment.occupancy - _occupancy!).abs() > motionDelta) {
      _alignedSince = now;
      _occupancy = assessment.occupancy;
      return false;
    }
    _occupancy = assessment.occupancy;
    _alignedSince ??= now;
    return now.difference(_alignedSince!) >= hold;
  }

  void reset() {
    _alignedSince = null;
    _occupancy = null;
  }
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
    this.recognizedText = '',
    this.faceCenterX,
    this.faceCount = 0,
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
      textCoverage = 0,
      recognizedText = '',
      faceCenterX = null,
      faceCount = 0;

  final bool available;
  final int alphanumericChars;
  final int blockCount;
  final double faceCoverage;
  final double? faceCenterX;
  final int faceCount;

  /// Lowercased OCR concatenated from overlay blocks. Empty when unknown.
  final String recognizedText;

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

  /// Document-like text layout, not a single logo on a mousepad.
  /// Does not match ID keywords.
  bool looksLikePrintedId({required bool requirePhoto}) {
    if (!available) return false;
    if (isConfidentNonDocument) return false;
    if (alphanumericChars < 16 || blockCount < 3) return false;
    if (requirePhoto) {
      if (faceCoverage >= IdImageMetrics.minFrontFaceCoverage) return true;
      return alphanumericChars >= 22 && blockCount >= 4;
    }
    return true;
  }

  /// Strong evidence this is a selfie or a phone screen — not a printed ID.
  ///
  /// Live capture must not treat a short OCR read (barcode, ID number) as a
  /// logo veto; ID backs often OCR as one or two blocks.
  bool get isConfidentNonDocument {
    if (!available) return false;
    if (textCoverage >= IdImageMetrics.maxScreenTextCoverage) return true;
    if (faceCoverage > IdImageMetrics.maxSelfieFaceCoverage) return true;
    return looksLikePaymentCard;
  }

  /// Payment-network copy is never a government ID, even if the card is ID-1.
  bool get looksLikePaymentCard {
    if (!available || recognizedText.isEmpty) return false;
    final text = recognizedText.toLowerCase();
    const terms = [
      'visa',
      'mastercard',
      'master card',
      'american express',
      'unionpay',
      'valid thru',
      'debit card',
      'credit card',
    ];
    for (final term in terms) {
      if (text.contains(term)) return true;
    }
    if (RegExp(r'\bamex\b').hasMatch(text)) return true;
    return false;
  }
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

  /// Live overlay is landscape ID-1. Portrait blobs (mice, phones on end)
  /// must not count as aligned.
  static const double liveMinAspect = 1.18;
  static const double liveMaxAspect = 1.98;
  static const int liveMinBands = 3;
  static const double liveMinBorderScore = 0.28;
  static const double liveMinCornerFill = 0.22;
  static const double liveMinInteriorMean = 78;
  static const double liveMinLightFraction = 0.32;
  static const double liveMinModuleScore = 0.24;
  static const double liveMaxModuleScore = 0.70;

  /// Checkerboard density above ordinary ID text bands. Empty-OCR backs only.
  static const double denseQrModuleScore = 0.80;

  static const int minInWindowChars = 8;
  static const int minInWindowBlocks = 2;
  static const double minFrontFaceCoverage = 0.04;
  static const double maxFrontFaceCoverage = 0.38;
  static const double maxSelfieFaceCoverage = 0.42;
  static const double highOccupancy = 0.85;
  static const double minCardBorderScore = 0.22;
  static const double maxScreenTextCoverage = 0.75;

  /// Specular hotspots on glossy PVC. White card stock itself sits ~180–230.
  static const int glareLuma = 248;
  static const double maxGlareFraction = 0.12;

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

    final window = documentWindow(luma, width, height);
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
    if (cropLuma.isEmpty || cropW < 8 || cropH < 8 || n < 1) {
      return IdQualityResult.fail(IdQualityIssue.notId);
    }
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
        'border=${geometry.borderScore.toStringAsFixed(2)} '
        'corners=${geometry.cornerFill.toStringAsFixed(2)} '
        'interior=${geometry.interiorMean.toStringAsFixed(0)} '
        'light=${geometry.lightFraction.toStringAsFixed(2)} '
        'frame=${geometry.frameMean.toStringAsFixed(0)} '
        'frameLight=${geometry.frameLight.toStringAsFixed(2)} '
        'module=${geometry.moduleScore.toStringAsFixed(2)} '
        'solid=${geometry.solidity.toStringAsFixed(2)} crop=${cropW}x$cropH';

    // Framing before document-ness so a partial ID is "align the edges",
    // not "no ID". Size after document-ness so a charger is not "too far".
    if (geometry.poorlyFramed) {
      return IdQualityResult.fail(IdQualityIssue.poorFraming, debug: debug);
    }
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
        evidence.faceCoverage < minFrontFaceCoverage &&
        geometry.moduleScore < liveMinModuleScore) {
      return IdQualityResult.fail(IdQualityIssue.notId, debug: debug);
    }
    if (stddev < minContrast) {
      return IdQualityResult.fail(IdQualityIssue.lowContrast, debug: debug);
    }

    final glare = _glareFraction(cropLuma);
    if (glare >= maxGlareFraction) {
      return IdQualityResult.fail(IdQualityIssue.glare, debug: debug);
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
  /// Does not classify ID type or authenticity. Callers that can run ML Kit
  /// should also apply [confirmLiveDocument] before treating the frame as an ID.
  static bool isLiveAligned({
    required List<int> luma,
    required int width,
    required int height,
  }) => assessLivePreview(luma: luma, width: width, height: height).isAligned;

  /// Same checks as [isLiveAligned], plus a user-facing reason when it fails.
  ///
  /// Luma geometry only. A dark mouse on a textured pad can still look
  /// rectangular; [confirmLiveDocument] is the printed-text gate.
  static LiveIdAssessment assessLivePreview({
    required List<int> luma,
    required int width,
    required int height,
  }) {
    if (luma.isEmpty || width < 8 || height < 8) {
      return const LiveIdAssessment.searching();
    }

    final window = centerCardWindow(width, height);
    final crop = extractWindow(luma, width, height, window);
    final stats = _lumaStats(crop.luma);
    final geometry = measureGeometry(
      crop.luma,
      crop.width,
      crop.height,
      stats.mean,
    );

    final lightingOk =
        stats.mean >= minBrightness && stats.stddev >= minContrast;
    final filled =
        geometry.occupancy >= liveMinOccupancy ||
        (geometry.moduleScore >= liveMinModuleScore &&
            geometry.frameLight >= liveMinLightFraction * 0.7);
    final looksCard = _looksLikePrintedCardLive(geometry);

    if (lightingOk && filled && looksCard) {
      final blur = reblurScoreOnRegion(
        crop.luma,
        crop.width,
        crop.height,
        geometry,
      );
      if (blur < slightlySoftReblur) {
        return LiveIdAssessment(
          status: LiveIdStatus.aligned,
          occupancy: geometry.occupancy,
        );
      }
      return LiveIdAssessment(
        status: LiveIdStatus.blurry,
        occupancy: geometry.occupancy,
      );
    }

    if (geometry.occupancy < IdCaptureGuide.liveSearchingOccupancy) {
      return LiveIdAssessment(
        status: LiveIdStatus.searching,
        occupancy: geometry.occupancy,
      );
    }
    if (!lightingOk) {
      return LiveIdAssessment(
        status: LiveIdStatus.tooDark,
        occupancy: geometry.occupancy,
      );
    }
    if (!filled) {
      return LiveIdAssessment(
        status: LiveIdStatus.tooFar,
        occupancy: geometry.occupancy,
      );
    }
    if (geometry.poorlyFramed || !geometry.cardLikeAspect) {
      return LiveIdAssessment(
        status: LiveIdStatus.poorlyFramed,
        occupancy: geometry.occupancy,
      );
    }
    return LiveIdAssessment(
      status: LiveIdStatus.notId,
      occupancy: geometry.occupancy,
    );
  }

  /// Live OCR is a veto, not a second admission exam.
  ///
  /// Stream ML Kit on a CameraImage is often empty or mis-framed, so unknown
  /// OCR must not block a light printed card — the JPEG still is the
  /// fail-closed gate. A selfie, screen, or payment card still blocks.
  static LiveIdAssessment confirmLiveDocument(
    LiveIdAssessment luma, {
    required DocumentEvidence evidence,
  }) {
    if (!luma.isAligned) return luma;
    if (!evidence.available) return luma;
    if (evidence.isConfidentNonDocument) {
      return LiveIdAssessment(
        status: LiveIdStatus.notId,
        occupancy: luma.occupancy,
      );
    }
    return luma;
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

  /// Overlay hole for a portrait camera still, or the full frame when the
  /// photo is already cropped to a landscape ID.
  static IdCardWindow documentWindow(List<int> luma, int width, int height) {
    final guide = centerCardWindow(width, height);
    if (width < 16 || height < 16 || luma.length < width * height) {
      return guide;
    }
    final aspect = width / height;
    if (aspect < liveMinAspect || aspect > liveMaxAspect) return guide;
    final stats = _lumaStats(luma);
    final geometry = measureGeometry(luma, width, height, stats.mean);
    // Saved captures are already an ID-1 crop. A QR on the back can make the
    // bbox square; still use the full bitmap instead of punching a second hole.
    if (geometry.occupancy >= 0.58) {
      return IdCardWindow(x0: 0, y0: 0, width: width, height: height);
    }
    return guide;
  }

  /// JPEG crop for review/upload: the on-screen ID-1 guide, tightened to the
  /// card when the detected bbox is itself a landscape ID.
  static IdCardWindow captureCropWindow({
    required int imageWidth,
    required int imageHeight,
    IdDocumentGeometry? overlayGeometry,
  }) {
    final overlay = centerCardWindow(imageWidth, imageHeight);
    final g = overlayGeometry;
    if (g == null || g.maxX <= g.minX || g.maxY <= g.minY) {
      return overlay;
    }
    if (g.aspectRatio < liveMinAspect || g.aspectRatio > liveMaxAspect) {
      return overlay;
    }
    if (g.occupancy < 0.40 || g.occupancy > 0.96) return overlay;

    final padX = ((g.maxX - g.minX) * 0.06).round().clamp(2, 20);
    final padY = ((g.maxY - g.minY) * 0.08).round().clamp(2, 16);
    final x0 = _clamp(overlay.x0 + g.minX - padX, 0, imageWidth - 8);
    final y0 = _clamp(overlay.y0 + g.minY - padY, 0, imageHeight - 8);
    final x1 = _clamp(overlay.x0 + g.maxX + padX, x0 + 8, imageWidth - 1);
    final y1 = _clamp(overlay.y0 + g.maxY + padY, y0 + 8, imageHeight - 1);
    return IdCardWindow(
      x0: x0,
      y0: y0,
      width: x1 - x0 + 1,
      height: y1 - y0 + 1,
    );
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
      final srcY = window.y0 + y;
      if (srcY < 0 || srcY >= srcHeight) break;
      final srcRow = srcY * srcWidth + window.x0;
      final dstRow = y * window.width;
      for (var x = 0; x < window.width; x++) {
        final src = srcRow + x;
        if (src < 0 || src >= luma.length) break;
        out[dstRow + x] = luma[src];
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
    if (geometry.interiorMean < 60 && geometry.frameMean < 60) {
      return false;
    }
    if (geometry.lightFraction < 0.18 && geometry.frameLight < 0.18) {
      return false;
    }

    if (!evidence.available) {
      return _hasPrintedCardStructure(geometry);
    }

    if (evidence.textCoverage >= maxScreenTextCoverage) return false;
    if (evidence.looksLikePaymentCard) return false;

    final hasText =
        evidence.alphanumericChars >= minInWindowChars &&
        evidence.blockCount >= minInWindowBlocks;
    final hasPortrait =
        evidence.faceCoverage >= minFrontFaceCoverage &&
        evidence.faceCoverage <= maxFrontFaceCoverage;
    final qrGuide =
        geometry.moduleScore >= liveMinModuleScore &&
        geometry.moduleScore <= liveMaxModuleScore &&
        geometry.frameLight >= liveMinLightFraction;
    // Text bands also lift module score (~0.75). Only a dense checkerboard
    // with no OCR is treated as a QR ID back.
    final denseQr =
        geometry.moduleScore >= denseQrModuleScore &&
        geometry.frameLight >= liveMinLightFraction;

    if (hasText) {
      if (!geometry.cardLikeAspect && !qrGuide) return false;
      if (requireIdPhoto) {
        return hasPortrait || geometry.bandCount >= 3 || qrGuide;
      }
      return geometry.bandCount >= 2 || hasPortrait || qrGuide;
    }

    if (requireIdPhoto && hasPortrait && _hasPrintedCardStructure(geometry)) {
      return true;
    }
    if (!requireIdPhoto && denseQr && _hasPrintedCardStructure(geometry)) {
      return true;
    }
    // ML Kit ran. Empty OCR without a portrait or QR is not an ID.
    return false;
  }

  /// Independent card cues used for live auto-capture and OCR-less fallback.
  /// Occupancy/aspect alone is not enough — a mouse can fill the frame.
  static bool _hasPrintedCardStructure(IdDocumentGeometry geometry) {
    if (!geometry.cardLikeAspect || geometry.poorlyFramed) {
      if (geometry.poorlyFramed) return false;
      if (geometry.moduleScore < liveMinModuleScore ||
          geometry.moduleScore > liveMaxModuleScore ||
          geometry.frameLight < liveMinLightFraction ||
          geometry.frameMean < liveMinInteriorMean) {
        return false;
      }
    } else if (geometry.bandCount < 3 &&
        (geometry.moduleScore < liveMinModuleScore ||
            (geometry.moduleScore > liveMaxModuleScore &&
                geometry.occupancy < highOccupancy))) {
      return false;
    }
    // When the card fills the guide, overlay edges sit on the card itself so
    // the bbox "border" score can collapse. Still require a rectangular edge
    // when the object is only mid-sized in the frame.
    final fillsFrame = geometry.occupancy >= highOccupancy;
    if (!fillsFrame && geometry.borderScore < minCardBorderScore) {
      return false;
    }
    // Rounded objects leave the AABB corners empty (desk/background).
    // A white ID on a white tray has no corner contrast — still accept when
    // the interior is light printed stock with text bands.
    if (geometry.cornerFill < 0.22 && !_lightPrintedBands(geometry)) {
      return false;
    }
    if (geometry.interiorMean < 60 && geometry.frameMean < 60) {
      return false;
    }
    if (geometry.lightFraction < 0.18 && geometry.frameLight < 0.18) {
      return false;
    }
    return true;
  }

  static bool _lightPrintedBands(IdDocumentGeometry geometry) =>
      (geometry.interiorMean >= liveMinInteriorMean ||
          geometry.frameMean >= liveMinInteriorMean) &&
      (geometry.lightFraction >= liveMinLightFraction ||
          geometry.frameLight >= liveMinLightFraction) &&
      geometry.bandCount >= liveMinBands;

  static bool _looksLikePrintedCardLive(IdDocumentGeometry geometry) {
    if (geometry.poorlyFramed) return false;

    final lightGuide =
        geometry.frameMean >= liveMinInteriorMean &&
        geometry.frameLight >= liveMinLightFraction;
    final lightObject =
        geometry.interiorMean >= liveMinInteriorMean &&
        geometry.lightFraction >= liveMinLightFraction;
    if (!lightGuide && !lightObject) return false;

    final printed =
        geometry.bandCount >= liveMinBands ||
        (geometry.moduleScore >= liveMinModuleScore &&
            geometry.moduleScore <= liveMaxModuleScore);
    if (!printed) return false;

    final landscapeCard =
        geometry.aspectRatio >= liveMinAspect &&
        geometry.aspectRatio <= liveMaxAspect &&
        geometry.cardLikeAspect;
    final printedInGuide =
        printed &&
        lightGuide &&
        geometry.moduleScore >= liveMinModuleScore &&
        geometry.moduleScore <= liveMaxModuleScore &&
        (geometry.occupancy >= 0.22 || geometry.bandCount >= 1);
    if (!landscapeCard && !printedInGuide) return false;

    if (geometry.cornerFill < liveMinCornerFill &&
        !_lightPrintedBands(geometry) &&
        geometry.moduleScore < liveMinModuleScore) {
      return false;
    }
    if (geometry.occupancy < 0.90 &&
        geometry.borderScore < liveMinBorderScore &&
        !landscapeCard &&
        geometry.moduleScore < liveMinModuleScore) {
      return false;
    }
    return true;
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
    final solidity = hits / (boxW * boxH);
    final cornerFill = _cornerFillScore(
      luma,
      width,
      height,
      minX,
      maxX,
      minY,
      maxY,
      border,
    );
    final interiorMean = _interiorMean(luma, width, minX, maxX, minY, maxY);
    final lightFraction = _lightPixelFraction(
      luma,
      width,
      minX,
      maxX,
      minY,
      maxY,
    );
    final portraitWellScore = _portraitWellScore(
      luma,
      width,
      minX,
      maxX,
      minY,
      maxY,
    );
    final frameMean = _interiorMean(luma, width, 0, width - 1, 0, height - 1);
    final frameLight = _lightPixelFraction(
      luma,
      width,
      0,
      width - 1,
      0,
      height - 1,
    );
    final moduleScore = _moduleScore(luma, width, height);
    final pad = (width < height ? width : height) * 0.08;
    return IdDocumentGeometry(
      occupancy: occupancy,
      aspectRatio: aspect,
      bandCount: bands,
      borderScore: borderScore,
      solidity: solidity,
      cornerFill: cornerFill,
      interiorMean: interiorMean,
      lightFraction: lightFraction,
      frameMean: frameMean,
      frameLight: frameLight,
      moduleScore: moduleScore,
      portraitWellScore: portraitWellScore,
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
          final dF = (original[y * width + x] - original[y * width + x - 1])
              .abs();
          final dB = (blurred[y * width + x] - blurred[y * width + x - 1])
              .abs();
          sumOrig += dF;
          sumKeep += dF > dB ? dF - dB : 0;
        }
      }
    } else {
      for (var y = 1; y < height; y++) {
        for (var x = 0; x < width; x++) {
          final dF = (original[y * width + x] - original[(y - 1) * width + x])
              .abs();
          final dB = (blurred[y * width + x] - blurred[(y - 1) * width + x])
              .abs();
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
    final threshold = mean * 1.22;
    const minRun = 2;
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

  /// How much of the four bbox corners is document rather than table/background.
  /// A rounded object (mouse) leaves empty corners; a printed ID fills them.
  static double _cornerFillScore(
    List<int> luma,
    int width,
    int height,
    int minX,
    int maxX,
    int minY,
    int maxY,
    int border,
  ) {
    final boxW = maxX - minX + 1;
    final boxH = maxY - minY + 1;
    if (boxW < 8 || boxH < 8) return 0;
    final cw = (boxW * 0.18).clamp(3, 10).round();
    final ch = (boxH * 0.22).clamp(3, 10).round();
    var filled = 0;
    var total = 0;

    void patch(int x0, int y0) {
      final x1 = _clamp(x0 + cw - 1, minX, maxX);
      final y1 = _clamp(y0 + ch - 1, minY, maxY);
      final xs = _clamp(x0, minX, maxX);
      final ys = _clamp(y0, minY, maxY);
      for (var y = ys; y <= y1; y++) {
        for (var x = xs; x <= x1; x++) {
          total++;
          final value = luma[y * width + x];
          if ((value - border).abs() >= 20) filled++;
        }
      }
    }

    patch(minX, minY);
    patch(maxX - cw + 1, minY);
    patch(minX, maxY - ch + 1);
    patch(maxX - cw + 1, maxY - ch + 1);
    return total == 0 ? 0 : filled / total;
  }

  static ({int x0, int x1, int y0, int y1})? _insetBox(
    int minX,
    int maxX,
    int minY,
    int maxY,
  ) {
    final boxW = maxX - minX + 1;
    final boxH = maxY - minY + 1;
    final ix = (boxW * 0.08).round().clamp(1, 8);
    final iy = (boxH * 0.08).round().clamp(1, 8);
    final x0 = minX + ix;
    final x1 = maxX - ix;
    final y0 = minY + iy;
    final y1 = maxY - iy;
    if (x1 <= x0 || y1 <= y0) return null;
    return (x0: x0, x1: x1, y0: y0, y1: y1);
  }

  /// Mean luminance inside the detected object. Printed IDs are light PVC.
  static double _interiorMean(
    List<int> luma,
    int width,
    int minX,
    int maxX,
    int minY,
    int maxY,
  ) {
    final box = _insetBox(minX, maxX, minY, maxY);
    if (box == null) return 0;
    var sum = 0;
    var n = 0;
    for (var y = box.y0; y <= box.y1; y++) {
      final row = y * width;
      for (var x = box.x0; x <= box.x1; x++) {
        sum += luma[row + x];
        n++;
      }
    }
    return n == 0 ? 0 : sum / n;
  }

  /// Fraction of interior pixels that look like light card stock, not a
  /// black mouse or a dark mousepad.
  static double _lightPixelFraction(
    List<int> luma,
    int width,
    int minX,
    int maxX,
    int minY,
    int maxY,
  ) {
    final box = _insetBox(minX, maxX, minY, maxY);
    if (box == null) return 0;
    var light = 0;
    var n = 0;
    for (var y = box.y0; y <= box.y1; y++) {
      final row = y * width;
      for (var x = box.x0; x <= box.x1; x++) {
        n++;
        if (luma[row + x] >= 110) light++;
      }
    }
    return n == 0 ? 0 : light / n;
  }

  /// Fraction of crop pixels that look like specular glare, not white PVC.
  static double _glareFraction(List<int> luma) {
    if (luma.isEmpty) return 0;
    var hot = 0;
    for (final value in luma) {
      if (value >= glareLuma) hot++;
    }
    return hot / luma.length;
  }

  /// Left-vs-right luminance gap on a typical ID portrait layout.
  /// A uniform blob (mouse, charger) scores near zero.
  static double _portraitWellScore(
    List<int> luma,
    int width,
    int minX,
    int maxX,
    int minY,
    int maxY,
  ) {
    final box = _insetBox(minX, maxX, minY, maxY);
    if (box == null) return 0;
    final boxW = box.x1 - box.x0 + 1;
    final boxH = box.y1 - box.y0 + 1;
    if (boxW < 16 || boxH < 12) return 0;
    final split = (boxW * 0.32).round().clamp(4, boxW ~/ 3);
    final yPad = (boxH * 0.18).round().clamp(1, boxH ~/ 4);
    final y0 = box.y0 + yPad;
    final y1 = box.y1 - yPad;
    if (y1 <= y0) return 0;

    double regionMean(int x0, int x1) {
      var sum = 0;
      var n = 0;
      for (var y = y0; y <= y1; y++) {
        final row = y * width;
        for (var x = x0; x <= x1; x++) {
          sum += luma[row + x];
          n++;
        }
      }
      return n == 0 ? 0 : sum / n;
    }

    final left = regionMean(box.x0, box.x0 + split);
    final right = regionMean(box.x1 - split, box.x1);
    return (left - right).abs() / 255.0;
  }

  /// Fraction of inner guide cells with QR/barcode-like local contrast.
  /// Perimeter cells are ignored so a card border is not treated as a QR.
  static double _moduleScore(List<int> luma, int width, int height) {
    const cols = 10;
    const rows = 6;
    if (width < cols * 2 || height < rows * 2) return 0;
    var busy = 0;
    var total = 0;
    for (var r = 1; r < rows - 1; r++) {
      for (var c = 1; c < cols - 1; c++) {
        total++;
        final x0 = (c * width) ~/ cols;
        final x1 = ((c + 1) * width) ~/ cols - 1;
        final y0 = (r * height) ~/ rows;
        final y1 = ((r + 1) * height) ~/ rows - 1;
        if (x1 <= x0 || y1 <= y0) continue;
        var minV = 255;
        var maxV = 0;
        for (var y = y0; y <= y1; y++) {
          final row = y * width;
          for (var x = x0; x <= x1; x++) {
            final v = luma[row + x];
            if (v < minV) minV = v;
            if (v > maxV) maxV = v;
          }
        }
        if (maxV - minV >= 90) busy++;
      }
    }
    return total == 0 ? 0 : busy / total;
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
    this.solidity = 0,
    this.cornerFill = 0,
    this.interiorMean = 0,
    this.lightFraction = 0,
    this.frameMean = 0,
    this.frameLight = 0,
    this.moduleScore = 0,
    this.portraitWellScore = 0,
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
      solidity = 0,
      cornerFill = 0,
      interiorMean = 0,
      lightFraction = 0,
      frameMean = 0,
      frameLight = 0,
      moduleScore = 0,
      portraitWellScore = 0,
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
  final double solidity;
  final double cornerFill;
  final double interiorMean;
  final double lightFraction;
  final double frameMean;
  final double frameLight;
  final double moduleScore;
  final double portraitWellScore;
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
