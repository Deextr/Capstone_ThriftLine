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
  lookingAway,
  tooDark,
  overexposed,
  blurry,
  occluded,
  headCovering,
  eyeCovering,
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
    SelfieQualityIssue.multipleFaces => 'Only one person should be visible.',
    SelfieQualityIssue.tooSmall =>
      'Move closer so your face is clearly visible.',
    SelfieQualityIssue.poorlyFramed =>
      'Make sure your whole face is inside the frame.',
    SelfieQualityIssue.lookingAway =>
      'Look directly at the camera and try again.',
    SelfieQualityIssue.tooDark =>
      'The image is too dark. Please move to a better-lit area.',
    SelfieQualityIssue.overexposed =>
      'Your face is too bright. Move away from strong light and try again.',
    SelfieQualityIssue.blurry =>
      'Your face appears blurry. Please hold your phone steady and retake the selfie.',
    SelfieQualityIssue.occluded => 'Keep your face uncovered and try again.',
    SelfieQualityIssue.headCovering => 'Please remove your cap or hat.',
    SelfieQualityIssue.eyeCovering => 'Please remove your glasses.',
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
    this.hasLeftEye = false,
    this.hasRightEye = false,
    this.hasNose = false,
    this.hasMouth = false,
    this.leftEyeY,
    this.rightEyeY,
    this.yaw,
    this.pitch,
  });

  /// Bounding box in image coordinates. May extend slightly outside 0–1.
  final double left;
  final double top;
  final double right;
  final double bottom;
  final bool looksOccluded;
  final bool hasLeftEye;
  final bool hasRightEye;
  final bool hasNose;
  final bool hasMouth;

  /// Normalized landmark Y, when ML Kit returned the eyes.
  final double? leftEyeY;
  final double? rightEyeY;

  /// Head rotation in degrees from ML Kit, when the detector provided it.
  final double? yaw;
  final double? pitch;

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
    final smaller = visibleCoverage < other.visibleCoverage
        ? visibleCoverage
        : other.visibleCoverage;
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
  }) => livenessPassed && imageQuality.passed;
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
  static const double maxBrightness = 244;
  static const double blurryReblur = 0.62;
  static const double maxFaceCoverage = 0.62;

  /// Drops ML Kit duplicate boxes and tiny false positives, then keeps
  /// people who are large enough to be a second person in the selfie.
  static List<SelfieDetectedFace> selectPeople(List<SelfieDetectedFace> faces) {
    final countable =
        faces
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
    return other.visibleCoverage >=
        primary.visibleCoverage * minSecondaryRelativeSize;
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
    final covering = liveObstruction(
      face: face,
      luma: luma,
      lumaWidth: width,
      lumaHeight: height,
      yaw: face.yaw ?? 0,
    );
    if (covering == SelfieObstruction.occluded) {
      return SelfieQualityResult.fail(SelfieQualityIssue.occluded);
    }
    if (covering == SelfieObstruction.headCovering) {
      return SelfieQualityResult.fail(SelfieQualityIssue.headCovering);
    }
    if (covering == SelfieObstruction.eyeCovering) {
      return SelfieQualityResult.fail(SelfieQualityIssue.eyeCovering);
    }
    if (face.visibleCoverage < minFaceCoverage) {
      return SelfieQualityResult.fail(SelfieQualityIssue.tooSmall);
    }
    if (face.visibleCoverage > maxFaceCoverage) {
      return SelfieQualityResult.fail(SelfieQualityIssue.poorlyFramed);
    }
    if (face.inFrameFraction < minInFrameFraction) {
      return SelfieQualityResult.fail(SelfieQualityIssue.poorlyFramed);
    }
    if ((face.centerX - 0.5).abs() > maxOffCenter ||
        (face.centerY - 0.5).abs() > maxOffCenter) {
      return SelfieQualityResult.fail(SelfieQualityIssue.poorlyFramed);
    }
    if ((face.yaw != null && face.yaw!.abs() > SelfieCaptureGuide.maxYaw) ||
        (face.pitch != null &&
            face.pitch!.abs() > SelfieCaptureGuide.maxPitch)) {
      return SelfieQualityResult.fail(SelfieQualityIssue.lookingAway);
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
    if (mean > maxBrightness) {
      return SelfieQualityResult.fail(
        SelfieQualityIssue.overexposed,
        debug: debug,
      );
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

  /// Baseball-cap visor: a dark bar on the eyebrows, much darker than the
  /// cheeks. Center-only bangs do not satisfy left+right darkness.
  ///
  /// The strip is anchored to the eyes. A band that started above the face
  /// box mixed hair into the sample, so uncovered dark hair was flagged as
  /// a cap and the flag stayed true after the cap was removed.
  ///
  /// By default this returns false when the head is turned, because look-left
  /// / look-right shadowing is not a visor. Pass [allowTurnedPose] during
  /// those live challenges so a cap added mid-turn can still be rejected.
  static bool visorLooksPresent({
    required List<int> luma,
    required int width,
    required int height,
    required SelfieDetectedFace face,
    bool allowTurnedPose = false,
    double? poseYaw,
  }) {
    if (luma.length < width * height || width < 16 || height < 16) {
      return false;
    }
    final yaw = poseYaw ?? face.yaw;
    final turned =
        (yaw != null && yaw.abs() > SelfieCaptureGuide.maxYaw) ||
        (face.pitch != null && face.pitch!.abs() > SelfieCaptureGuide.maxPitch);
    if (turned && !allowTurnedPose) {
      return false;
    }
    if (face.width <= 0 || face.height <= 0) return false;

    final eyeY = (face.leftEyeY != null && face.rightEyeY != null)
        ? (face.leftEyeY! + face.rightEyeY!) / 2
        : face.top + face.height * 0.38;
    // Sit on the brows. Do not start above the face box — that samples hair.
    final bandBottom = eyeY;
    final bandTop = eyeY - face.height * SelfieCaptureGuide.visorBandHeight;
    if (bandBottom - bandTop < 0.04) return false;

    final third = face.width / 3;
    final left = _regionMean(
      luma,
      width,
      height,
      face.left,
      face.left + third,
      bandTop,
      bandBottom,
    );
    final mid = _regionMean(
      luma,
      width,
      height,
      face.left + third,
      face.left + third * 2,
      bandTop,
      bandBottom,
    );
    final right = _regionMean(
      luma,
      width,
      height,
      face.left + third * 2,
      face.right,
      bandTop,
      bandBottom,
    );
    final cheek = _regionMean(
      luma,
      width,
      height,
      face.left + face.width * 0.18,
      face.right - face.width * 0.18,
      face.top + face.height * 0.48,
      face.top + face.height * 0.78,
    );
    if (left == null || mid == null || right == null || cheek == null) {
      return false;
    }
    if (cheek < 55) return false;

    final delta = turned
        ? SelfieCaptureGuide.visorDarkDelta + 10
        : SelfieCaptureGuide.visorDarkDelta;
    // Left+mid+right darkness is the visor signature. Do not also require a
    // sharp row jump: a still uniform brim has almost no jump after
    // downsample, so detection only fired when motion (hair, head) created
    // an edge.
    return cheek - left >= delta &&
        cheek - mid >= delta &&
        cheek - right >= delta;
  }

  static double? _regionMean(
    List<int> luma,
    int width,
    int height,
    double left,
    double right,
    double top,
    double bottom,
  ) {
    var x0 = (left * width).floor();
    var x1 = (right * width).ceil();
    var y0 = (top * height).floor();
    var y1 = (bottom * height).ceil();
    if (x0 < 0) x0 = 0;
    if (y0 < 0) y0 = 0;
    if (x1 > width) x1 = width;
    if (y1 > height) y1 = height;
    if (x1 <= x0 || y1 <= y0) return null;
    var sum = 0;
    var count = 0;
    for (var y = y0; y < y1; y++) {
      final row = y * width;
      for (var x = x0; x < x1; x++) {
        sum += luma[row + x];
        count++;
      }
    }
    if (count < 12) return null;
    return sum / count;
  }

  /// Live and still covering check used on every challenge frame.
  ///
  /// Result depends only on this frame's face + luma. A previous cap hit
  /// must not keep returning covering after the visor is gone.
  ///
  /// Clear prescription glasses do not change ML Kit landmarks or luma enough
  /// to detect without false rejects. Dark glasses are caught as [eyeCovering].
  static SelfieObstruction liveObstruction({
    required SelfieDetectedFace face,
    List<int>? luma,
    int? lumaWidth,
    int? lumaHeight,
    double yaw = 0,
    bool eyesClosed = false,
    bool allowTurnedPose = false,
  }) {
    final turned = yaw.abs() > SelfieCaptureGuide.maxYaw;
    if (turned) {
      if (!face.hasNose &&
          !face.hasMouth &&
          (face.hasLeftEye || face.hasRightEye)) {
        return SelfieObstruction.occluded;
      }
    } else if (face.looksOccluded) {
      return SelfieObstruction.occluded;
    }

    if (luma == null || lumaWidth == null || lumaHeight == null) {
      return SelfieObstruction.none;
    }

    if (visorLooksPresent(
      luma: luma,
      width: lumaWidth,
      height: lumaHeight,
      face: face,
      allowTurnedPose: allowTurnedPose,
      poseYaw: face.yaw ?? yaw,
    )) {
      return SelfieObstruction.headCovering;
    }

    if (!eyesClosed &&
        eyeCoveringLooksPresent(
          luma: luma,
          width: lumaWidth,
          height: lumaHeight,
          face: face,
          yaw: yaw,
        )) {
      return SelfieObstruction.eyeCovering;
    }

    return SelfieObstruction.none;
  }

  /// Dark glasses / sunglasses: both eye wells much darker than the cheeks.
  /// Skipped when the head is nearly in profile so one eye socket is hidden.
  static bool eyeCoveringLooksPresent({
    required List<int> luma,
    required int width,
    required int height,
    required SelfieDetectedFace face,
    double yaw = 0,
  }) {
    if (luma.length < width * height || width < 16 || height < 16) {
      return false;
    }
    if (yaw.abs() > 28) return false;
    if (face.width <= 0 || face.height <= 0) return false;

    final eyeY = (face.leftEyeY != null && face.rightEyeY != null)
        ? (face.leftEyeY! + face.rightEyeY!) / 2
        : face.top + face.height * 0.38;
    final eyeTop = eyeY - face.height * 0.06;
    final eyeBottom = eyeY + face.height * 0.10;
    final leftEye = _regionMean(
      luma,
      width,
      height,
      face.left + face.width * 0.08,
      face.left + face.width * 0.42,
      eyeTop,
      eyeBottom,
    );
    final rightEye = _regionMean(
      luma,
      width,
      height,
      face.left + face.width * 0.58,
      face.right - face.width * 0.08,
      eyeTop,
      eyeBottom,
    );
    final cheek = _regionMean(
      luma,
      width,
      height,
      face.left + face.width * 0.18,
      face.right - face.width * 0.18,
      face.top + face.height * 0.48,
      face.top + face.height * 0.78,
    );
    final forehead = _regionMean(
      luma,
      width,
      height,
      face.left + face.width * 0.18,
      face.right - face.width * 0.18,
      face.top,
      face.top + face.height * 0.22,
    );
    if (leftEye == null || rightEye == null || cheek == null) return false;
    if (cheek < 55) return false;
    const delta = 48.0;
    if (cheek - leftEye < delta || cheek - rightEye < delta) return false;
    if (forehead != null &&
        forehead - leftEye < 10 &&
        forehead - rightEye < 10) {
      return false;
    }
    return true;
  }

  /// Shared live + still occlusion check from ML Kit landmarks.
  ///
  /// A mask often removes nose and mouth landmarks. During a head turn, one
  /// eye can disappear without a mask — callers must use [liveObstruction].
  static bool landmarksLookOccluded({
    required bool hasAnyLandmark,
    required bool hasLeftEye,
    required bool hasRightEye,
    required bool hasNose,
    required bool hasMouth,
  }) {
    if (!hasAnyLandmark) return false;
    final keyCount = [
      hasLeftEye,
      hasRightEye,
      hasNose,
      hasMouth,
    ].where((found) => found).length;
    return keyCount <= 1;
  }

  static ({double mean, double blur}) faceRegionStats(
    List<int> luma,
    int width,
    int height,
    SelfieDetectedFace face,
  ) {
    final crop = _faceCrop(luma, width, height, face);
    if (crop.width < 12 || crop.height < 12) {
      return (mean: 0, blur: 1);
    }
    return (
      mean: _mean(crop.luma),
      blur: IdImageMetrics.reblurScore(crop.luma, crop.width, crop.height),
    );
  }

  /// Live preview gate. Does not replace [evaluate] on the captured still.
  static LiveSelfieAssessment assessLive({
    required List<SelfieDetectedFace> faces,
    double? faceMean,
    double? blur,
    List<int>? luma,
    int? lumaWidth,
    int? lumaHeight,
  }) {
    final people = selectPeople(faces);
    if (people.isEmpty) {
      return const LiveSelfieAssessment(status: LiveSelfieStatus.noFace);
    }
    if (people.length > 1) {
      return const LiveSelfieAssessment(status: LiveSelfieStatus.multipleFaces);
    }

    final face = people.first;
    final covering = liveObstruction(
      face: face,
      luma: luma,
      lumaWidth: lumaWidth,
      lumaHeight: lumaHeight,
      yaw: face.yaw ?? 0,
      allowTurnedPose: true,
    );
    if (covering == SelfieObstruction.occluded) {
      return LiveSelfieAssessment(
        status: LiveSelfieStatus.occluded,
        coverage: face.visibleCoverage,
      );
    }
    if (covering == SelfieObstruction.headCovering) {
      return LiveSelfieAssessment(
        status: LiveSelfieStatus.headCovering,
        coverage: face.visibleCoverage,
      );
    }
    if (covering == SelfieObstruction.eyeCovering) {
      return LiveSelfieAssessment(
        status: LiveSelfieStatus.eyeCovering,
        coverage: face.visibleCoverage,
      );
    }
    if (face.visibleCoverage < minFaceCoverage) {
      return LiveSelfieAssessment(
        status: LiveSelfieStatus.tooFar,
        coverage: face.visibleCoverage,
      );
    }
    if (face.visibleCoverage > maxFaceCoverage) {
      return LiveSelfieAssessment(
        status: LiveSelfieStatus.tooClose,
        coverage: face.visibleCoverage,
      );
    }
    if (face.inFrameFraction < minInFrameFraction ||
        (face.centerX - 0.5).abs() > maxOffCenter ||
        (face.centerY - 0.5).abs() > maxOffCenter) {
      return LiveSelfieAssessment(
        status: LiveSelfieStatus.offFrame,
        coverage: face.visibleCoverage,
      );
    }
    if ((face.yaw != null && face.yaw!.abs() > SelfieCaptureGuide.maxYaw) ||
        (face.pitch != null &&
            face.pitch!.abs() > SelfieCaptureGuide.maxPitch)) {
      return LiveSelfieAssessment(
        status: LiveSelfieStatus.lookingAway,
        coverage: face.visibleCoverage,
      );
    }
    if (faceMean != null && faceMean < minBrightness) {
      return LiveSelfieAssessment(
        status: LiveSelfieStatus.tooDark,
        coverage: face.visibleCoverage,
      );
    }
    if (faceMean != null && faceMean > maxBrightness) {
      return LiveSelfieAssessment(
        status: LiveSelfieStatus.tooBright,
        coverage: face.visibleCoverage,
      );
    }
    if (blur != null && blur >= blurryReblur) {
      return LiveSelfieAssessment(
        status: LiveSelfieStatus.blurry,
        coverage: face.visibleCoverage,
      );
    }
    return LiveSelfieAssessment(
      status: LiveSelfieStatus.aligned,
      coverage: face.visibleCoverage,
    );
  }
}

/// Tunables for live selfie auto-capture. Keep in sync with device testing.
class SelfieCaptureGuide {
  static const Duration liveAnalyzeInterval = Duration(milliseconds: 160);
  static const Duration autoCaptureHold = Duration(milliseconds: 900);

  /// Face must stay uncovered and front-facing this long before Face completes.
  static const Duration challengeFaceHold = Duration(milliseconds: 800);

  /// Look-left / look-right must be held this long with a clear face.
  static const Duration challengeTurnHold = Duration(milliseconds: 2500);

  static const double maxYaw = 15;
  static const double maxPitch = 18;
  static const double motionCoverageDelta = 0.06;

  /// Height of the visor strip above the eyes, as a fraction of face height.
  static const double visorBandHeight = 0.16;

  /// Cheek-minus-visor luma. Uncovered forehead is typically well below this.
  static const double visorDarkDelta = 42;
}

enum SelfieObstruction { none, occluded, headCovering, eyeCovering }

enum LiveSelfieStatus {
  noFace,
  multipleFaces,
  tooFar,
  tooClose,
  offFrame,
  lookingAway,
  occluded,
  headCovering,
  eyeCovering,
  tooDark,
  tooBright,
  blurry,
  aligned,
}

class LiveSelfieAssessment {
  const LiveSelfieAssessment({required this.status, this.coverage = 0});

  final LiveSelfieStatus status;
  final double coverage;

  bool get isAligned => status == LiveSelfieStatus.aligned;

  String get feedbackMessage => switch (status) {
    LiveSelfieStatus.noFace => 'Position your face within the frame',
    LiveSelfieStatus.multipleFaces => 'Only one person should be visible',
    LiveSelfieStatus.tooFar => 'Move closer to the camera',
    LiveSelfieStatus.tooClose => 'Move your face farther away',
    LiveSelfieStatus.offFrame => 'Move your face inside the frame',
    LiveSelfieStatus.lookingAway => 'Look directly at the camera',
    LiveSelfieStatus.occluded => 'Please remove your mask',
    LiveSelfieStatus.headCovering => 'Please remove your cap or hat',
    LiveSelfieStatus.eyeCovering => 'Please remove your glasses',
    LiveSelfieStatus.tooDark => 'Make sure your face is well-lit',
    LiveSelfieStatus.tooBright => 'Make sure your face is well-lit',
    LiveSelfieStatus.blurry => 'Hold your phone steady',
    LiveSelfieStatus.aligned => 'Face verified — hold still',
  };
}
