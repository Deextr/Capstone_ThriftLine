import 'selfie_image_quality.dart';

enum LivenessChallengeStep { face, lookRight, lookLeft, blink, capture }

class LivenessChallengeResult {
  const LivenessChallengeResult({
    required this.step,
    required this.done,
    required this.status,
    this.holdingPose = false,
  });

  final LivenessChallengeStep step;
  final Map<String, bool> done;
  final LiveSelfieStatus status;
  final bool holdingPose;

  bool get livenessComplete =>
      done['face'] == true &&
      done['lookRight'] == true &&
      done['lookLeft'] == true &&
      done['blink'] == true;
}

/// Step machine for look-at-camera → look-right → look-left → blink.
///
/// Covering checks run on every frame, including while the head is turned.
/// Look-left / look-right only complete after [turnHold] of a valid pose
/// with an uncovered face — a single yaw spike is not enough.
class LivenessChallengeSession {
  LivenessChallengeSession({
    this.turnHold = SelfieCaptureGuide.challengeTurnHold,
    this.faceHold = SelfieCaptureGuide.challengeFaceHold,
  });

  final Duration turnHold;
  final Duration faceHold;

  LivenessChallengeStep step = LivenessChallengeStep.face;
  final Map<String, bool> done = {
    'face': false,
    'lookRight': false,
    'lookLeft': false,
    'blink': false,
  };

  bool _eyesWereOpen = false;
  DateTime? _holdStarted;

  bool get isComplete =>
      done['face'] == true &&
      done['lookRight'] == true &&
      done['lookLeft'] == true &&
      done['blink'] == true;

  LivenessChallengeResult observe({
    required List<SelfieDetectedFace> faces,
    required double yaw,
    required bool eyesOpen,
    required bool eyesClosed,
    List<int>? luma,
    int? lumaWidth,
    int? lumaHeight,
    required DateTime now,
  }) {
    final people = SelfieImageMetrics.selectPeople(faces);
    if (people.isEmpty) {
      return _block(LiveSelfieStatus.noFace);
    }
    if (people.length > 1) {
      return _block(LiveSelfieStatus.multipleFaces);
    }

    final face = people.first;
    final frontal =
        step == LivenessChallengeStep.face ||
        step == LivenessChallengeStep.blink;
    if (frontal && face.visibleCoverage < SelfieImageMetrics.minFaceCoverage) {
      return _block(LiveSelfieStatus.tooFar);
    }

    final covering = SelfieImageMetrics.liveObstruction(
      face: face,
      luma: luma,
      lumaWidth: lumaWidth,
      lumaHeight: lumaHeight,
      yaw: yaw,
      eyesClosed: eyesClosed,
      allowTurnedPose: true,
    );
    if (covering != SelfieObstruction.none) {
      return _block(_statusFor(covering));
    }

    if (isComplete) {
      return LivenessChallengeResult(
        step: LivenessChallengeStep.capture,
        done: Map<String, bool>.from(done),
        status: LiveSelfieStatus.aligned,
      );
    }

    if (step == LivenessChallengeStep.blink) {
      return _observeBlink(eyesOpen: eyesOpen, eyesClosed: eyesClosed);
    }

    final poseOk = switch (step) {
      LivenessChallengeStep.face => yaw.abs() < 15,
      LivenessChallengeStep.lookRight => yaw < -16,
      LivenessChallengeStep.lookLeft => yaw > 16,
      LivenessChallengeStep.blink || LivenessChallengeStep.capture => false,
    };
    final hold = switch (step) {
      LivenessChallengeStep.face => faceHold,
      LivenessChallengeStep.lookRight ||
      LivenessChallengeStep.lookLeft => turnHold,
      LivenessChallengeStep.blink ||
      LivenessChallengeStep.capture => Duration.zero,
    };

    if (!poseOk) {
      _holdStarted = null;
      return _snapshot(holdingPose: false);
    }

    _holdStarted ??= now;
    if (now.difference(_holdStarted!) < hold) {
      return _snapshot(holdingPose: true);
    }

    return _advance();
  }

  LivenessChallengeResult _block(LiveSelfieStatus status) {
    _holdStarted = null;
    if (status == LiveSelfieStatus.occluded ||
        status == LiveSelfieStatus.headCovering ||
        status == LiveSelfieStatus.eyeCovering) {
      _eyesWereOpen = false;
    }
    return LivenessChallengeResult(
      step: step,
      done: Map<String, bool>.from(done),
      status: status,
    );
  }

  LivenessChallengeResult _snapshot({required bool holdingPose}) {
    return LivenessChallengeResult(
      step: step,
      done: Map<String, bool>.from(done),
      status: LiveSelfieStatus.aligned,
      holdingPose: holdingPose,
    );
  }

  LivenessChallengeResult _advance() {
    _holdStarted = null;
    switch (step) {
      case LivenessChallengeStep.face:
        done['face'] = true;
        step = LivenessChallengeStep.lookRight;
      case LivenessChallengeStep.lookRight:
        done['lookRight'] = true;
        step = LivenessChallengeStep.lookLeft;
      case LivenessChallengeStep.lookLeft:
        done['lookLeft'] = true;
        step = LivenessChallengeStep.blink;
      case LivenessChallengeStep.blink:
      case LivenessChallengeStep.capture:
        break;
    }
    return LivenessChallengeResult(
      step: step,
      done: Map<String, bool>.from(done),
      status: LiveSelfieStatus.aligned,
    );
  }

  LivenessChallengeResult _observeBlink({
    required bool eyesOpen,
    required bool eyesClosed,
  }) {
    if (eyesOpen) _eyesWereOpen = true;
    if (_eyesWereOpen && eyesClosed) {
      done['blink'] = true;
      step = LivenessChallengeStep.capture;
      _holdStarted = null;
    }
    return LivenessChallengeResult(
      step: step,
      done: Map<String, bool>.from(done),
      status: LiveSelfieStatus.aligned,
    );
  }

  static LiveSelfieStatus _statusFor(SelfieObstruction covering) {
    return switch (covering) {
      SelfieObstruction.none => LiveSelfieStatus.aligned,
      SelfieObstruction.occluded => LiveSelfieStatus.occluded,
      SelfieObstruction.headCovering => LiveSelfieStatus.headCovering,
      SelfieObstruction.eyeCovering => LiveSelfieStatus.eyeCovering,
    };
  }
}
