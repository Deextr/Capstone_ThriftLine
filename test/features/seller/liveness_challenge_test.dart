import 'package:flutter_test/flutter_test.dart';
import 'package:thriftline/features/seller/domain/liveness_challenge.dart';
import 'package:thriftline/features/seller/domain/selfie_image_quality.dart';

const _w = 160;
const _h = 200;

const _face = SelfieDetectedFace(
  left: 0.22,
  top: 0.18,
  right: 0.78,
  bottom: 0.82,
  hasLeftEye: true,
  hasRightEye: true,
  hasNose: true,
  hasMouth: true,
  leftEyeY: 0.40,
  rightEyeY: 0.40,
);

const _turnedRight = SelfieDetectedFace(
  left: 0.22,
  top: 0.18,
  right: 0.78,
  bottom: 0.82,
  hasLeftEye: true,
  hasRightEye: true,
  hasNose: true,
  hasMouth: true,
  leftEyeY: 0.40,
  rightEyeY: 0.40,
  yaw: -22,
);

const _turnedLeft = SelfieDetectedFace(
  left: 0.22,
  top: 0.18,
  right: 0.78,
  bottom: 0.82,
  hasLeftEye: true,
  hasRightEye: true,
  hasNose: true,
  hasMouth: true,
  leftEyeY: 0.40,
  rightEyeY: 0.40,
  yaw: 22,
);

List<int> _fill(int width, int height, int value) =>
    List<int>.filled(width * height, value);

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

List<int> _cappedSelfie() {
  final luma = _sharpSelfie();
  for (var y = 22; y <= 82; y++) {
    for (var x = 36; x <= 124; x++) {
      luma[y * _w + x] = 28;
    }
  }
  return luma;
}

/// Uniform visor with no sharp row edge (still user, downsampled brim).
List<int> _softCapSelfie() {
  final luma = _sharpSelfie();
  for (var y = 20; y <= 82; y++) {
    for (var x = 36; x <= 124; x++) {
      luma[y * _w + x] = 102;
    }
  }
  return luma;
}

/// Dark hair on the crown only — must not look like a visor on the brows.
List<int> _hairCrownSelfie() {
  final luma = _sharpSelfie();
  for (var y = 22; y <= 50; y++) {
    for (var x = 36; x <= 124; x++) {
      luma[y * _w + x] = 28;
    }
  }
  return luma;
}

List<int> _sunglassesSelfie() {
  final luma = _sharpSelfie();
  for (var y = 82; y <= 98; y++) {
    for (var x = 42; x <= 118; x++) {
      luma[y * _w + x] = 20;
    }
  }
  return luma;
}

List<int> _leftShadowSelfie() {
  final luma = _sharpSelfie();
  for (var y = 36; y <= 164; y++) {
    for (var x = 36; x <= 70; x++) {
      luma[y * _w + x] = 40;
    }
  }
  return luma;
}

LivenessChallengeResult _tick(
  LivenessChallengeSession session, {
  required DateTime now,
  required double yaw,
  List<SelfieDetectedFace> faces = const [_face],
  List<int>? luma,
  bool eyesOpen = true,
  bool eyesClosed = false,
}) {
  return session.observe(
    faces: faces,
    yaw: yaw,
    eyesOpen: eyesOpen,
    eyesClosed: eyesClosed,
    luma: luma ?? _sharpSelfie(),
    lumaWidth: _w,
    lumaHeight: _h,
    now: now,
  );
}

LivenessChallengeResult _completeFace(
  LivenessChallengeSession session,
  DateTime start,
) {
  _tick(session, now: start, yaw: 0);
  return _tick(
    session,
    now: start.add(const Duration(milliseconds: 800)),
    yaw: 0,
  );
}

void main() {
  group('visorLooksPresent during a head turn', () {
    test('skips a turned head unless allowTurnedPose is set', () {
      expect(
        SelfieImageMetrics.visorLooksPresent(
          luma: _cappedSelfie(),
          width: _w,
          height: _h,
          face: _turnedRight,
        ),
        isFalse,
      );
    });

    test('detects a cap while looking right when allowTurnedPose is set', () {
      expect(
        SelfieImageMetrics.visorLooksPresent(
          luma: _cappedSelfie(),
          width: _w,
          height: _h,
          face: _turnedRight,
          allowTurnedPose: true,
        ),
        isTrue,
      );
    });

    test('does not treat an uncovered turned face as a cap', () {
      expect(
        SelfieImageMetrics.visorLooksPresent(
          luma: _sharpSelfie(),
          width: _w,
          height: _h,
          face: _turnedRight,
          allowTurnedPose: true,
        ),
        isFalse,
      );
    });

    test('a uniform visor with no sharp edge is still a cap', () {
      expect(
        SelfieImageMetrics.visorLooksPresent(
          luma: _softCapSelfie(),
          width: _w,
          height: _h,
          face: _face,
        ),
        isTrue,
      );
    });

    test('dark hair on the crown is not a cap', () {
      expect(
        SelfieImageMetrics.visorLooksPresent(
          luma: _hairCrownSelfie(),
          width: _w,
          height: _h,
          face: _face,
        ),
        isFalse,
      );
    });

    test('one-sided turn shadow is not a cap', () {
      expect(
        SelfieImageMetrics.visorLooksPresent(
          luma: _leftShadowSelfie(),
          width: _w,
          height: _h,
          face: _turnedRight,
          allowTurnedPose: true,
        ),
        isFalse,
      );
    });
  });

  group('liveObstruction', () {
    test('a mask during a head turn is occluded', () {
      const masked = SelfieDetectedFace(
        left: 0.22,
        top: 0.18,
        right: 0.78,
        bottom: 0.82,
        hasLeftEye: true,
        hasRightEye: false,
        hasNose: false,
        hasMouth: false,
        yaw: 22,
      );
      expect(
        SelfieImageMetrics.liveObstruction(
          face: masked,
          yaw: 22,
          luma: _sharpSelfie(),
          lumaWidth: _w,
          lumaHeight: _h,
          allowTurnedPose: true,
        ),
        SelfieObstruction.occluded,
      );
    });

    test('losing one eye during a turn is not treated as a mask', () {
      const profile = SelfieDetectedFace(
        left: 0.22,
        top: 0.18,
        right: 0.78,
        bottom: 0.82,
        hasLeftEye: true,
        hasRightEye: false,
        hasNose: true,
        hasMouth: true,
        yaw: 22,
      );
      expect(
        SelfieImageMetrics.liveObstruction(
          face: profile,
          yaw: 22,
          luma: _sharpSelfie(),
          lumaWidth: _w,
          lumaHeight: _h,
          allowTurnedPose: true,
        ),
        SelfieObstruction.none,
      );
    });

    test('dark glasses are an eye covering', () {
      expect(
        SelfieImageMetrics.liveObstruction(
          face: _face,
          luma: _sunglassesSelfie(),
          lumaWidth: _w,
          lumaHeight: _h,
        ),
        SelfieObstruction.eyeCovering,
      );
    });

    test('closed eyes are not treated as glasses', () {
      expect(
        SelfieImageMetrics.liveObstruction(
          face: _face,
          luma: _sunglassesSelfie(),
          lumaWidth: _w,
          lumaHeight: _h,
          eyesClosed: true,
        ),
        SelfieObstruction.none,
      );
    });

    test('an uncovered face after a capped frame is not still covering', () {
      expect(
        SelfieImageMetrics.liveObstruction(
          face: _face,
          luma: _cappedSelfie(),
          lumaWidth: _w,
          lumaHeight: _h,
        ),
        SelfieObstruction.headCovering,
      );
      expect(
        SelfieImageMetrics.liveObstruction(
          face: _face,
          luma: _sharpSelfie(),
          lumaWidth: _w,
          lumaHeight: _h,
        ),
        SelfieObstruction.none,
      );
    });

    test('a cap while looking left is a head covering', () {
      expect(
        SelfieImageMetrics.liveObstruction(
          face: _turnedLeft,
          yaw: 22,
          luma: _cappedSelfie(),
          lumaWidth: _w,
          lumaHeight: _h,
          allowTurnedPose: true,
        ),
        SelfieObstruction.headCovering,
      );
    });
  });

  group('LivenessChallengeSession', () {
    test('Face does not complete on a single frontal frame', () {
      final session = LivenessChallengeSession();
      final t0 = DateTime.utc(2026, 9, 8);
      final first = _tick(session, now: t0, yaw: 0);
      expect(first.done['face'], isFalse);
      expect(first.holdingPose, isTrue);
      expect(first.step, LivenessChallengeStep.face);
    });

    test('Face completes only after the face hold', () {
      final session = LivenessChallengeSession();
      final t0 = DateTime.utc(2026, 9, 8);
      final done = _completeFace(session, t0);
      expect(done.done['face'], isTrue);
      expect(done.step, LivenessChallengeStep.lookRight);
    });

    test('look-right does not complete on a single yaw frame', () {
      final session = LivenessChallengeSession();
      final t0 = DateTime.utc(2026, 9, 8);
      _completeFace(session, t0);
      final t1 = t0.add(const Duration(seconds: 2));
      final first = _tick(
        session,
        now: t1,
        yaw: -22,
        faces: const [_turnedRight],
      );
      expect(first.done['lookRight'], isFalse);
      expect(first.holdingPose, isTrue);
      expect(first.step, LivenessChallengeStep.lookRight);
    });

    test('look-right completes after holding the pose uncovered', () {
      final session = LivenessChallengeSession();
      final t0 = DateTime.utc(2026, 9, 8);
      _completeFace(session, t0);
      final t1 = t0.add(const Duration(seconds: 2));
      _tick(session, now: t1, yaw: -22, faces: const [_turnedRight]);
      final done = _tick(
        session,
        now: t1.add(const Duration(milliseconds: 2500)),
        yaw: -22,
        faces: const [_turnedRight],
      );
      expect(done.done['lookRight'], isTrue);
      expect(done.step, LivenessChallengeStep.lookLeft);
    });

    test('a cap during look-right blocks the step even after 3 seconds', () {
      final session = LivenessChallengeSession();
      final t0 = DateTime.utc(2026, 9, 8);
      _completeFace(session, t0);
      final t1 = t0.add(const Duration(seconds: 2));
      final blocked = _tick(
        session,
        now: t1,
        yaw: -22,
        faces: const [_turnedRight],
        luma: _cappedSelfie(),
      );
      expect(blocked.status, LiveSelfieStatus.headCovering);
      expect(blocked.done['lookRight'], isFalse);
      expect(blocked.done['face'], isTrue);

      final stillBlocked = _tick(
        session,
        now: t1.add(const Duration(seconds: 3)),
        yaw: -22,
        faces: const [_turnedRight],
        luma: _cappedSelfie(),
      );
      expect(stillBlocked.status, LiveSelfieStatus.headCovering);
      expect(stillBlocked.done['lookRight'], isFalse);
      expect(stillBlocked.step, LivenessChallengeStep.lookRight);

      final cleared = _tick(
        session,
        now: t1.add(const Duration(seconds: 4)),
        yaw: -22,
        faces: const [_turnedRight],
        luma: _sharpSelfie(),
      );
      expect(cleared.status, isNot(LiveSelfieStatus.headCovering));
      expect(cleared.holdingPose, isTrue);
    });

    test('putting a cap on after Face still blocks look-left', () {
      final session = LivenessChallengeSession();
      final t0 = DateTime.utc(2026, 9, 8);
      _completeFace(session, t0);

      final t1 = t0.add(const Duration(seconds: 2));
      _tick(session, now: t1, yaw: -22, faces: const [_turnedRight]);
      _tick(
        session,
        now: t1.add(const Duration(milliseconds: 2500)),
        yaw: -22,
        faces: const [_turnedRight],
      );

      final blocked = _tick(
        session,
        now: t1.add(const Duration(seconds: 3)),
        yaw: 22,
        faces: const [_turnedLeft],
        luma: _cappedSelfie(),
      );
      expect(blocked.status, LiveSelfieStatus.headCovering);
      expect(blocked.done['lookLeft'], isFalse);
      expect(blocked.done['lookRight'], isTrue);
    });

    test('a mask during look-left stops the challenge', () {
      final session = LivenessChallengeSession();
      final t0 = DateTime.utc(2026, 9, 8);
      _completeFace(session, t0);
      final t1 = t0.add(const Duration(seconds: 2));
      _tick(session, now: t1, yaw: -22, faces: const [_turnedRight]);
      _tick(
        session,
        now: t1.add(const Duration(milliseconds: 2500)),
        yaw: -22,
        faces: const [_turnedRight],
      );

      const masked = SelfieDetectedFace(
        left: 0.22,
        top: 0.18,
        right: 0.78,
        bottom: 0.82,
        hasLeftEye: true,
        hasRightEye: true,
        hasNose: false,
        hasMouth: false,
        yaw: 22,
      );
      final blocked = _tick(
        session,
        now: t1.add(const Duration(seconds: 3)),
        yaw: 22,
        faces: const [masked],
      );
      expect(blocked.status, LiveSelfieStatus.occluded);
      expect(blocked.done['lookLeft'], isFalse);
    });

    test('dark glasses during look-right stop the challenge', () {
      final session = LivenessChallengeSession();
      final t0 = DateTime.utc(2026, 9, 8);
      _completeFace(session, t0);
      final blocked = _tick(
        session,
        now: t0.add(const Duration(seconds: 2)),
        yaw: -22,
        faces: const [_turnedRight],
        luma: _sunglassesSelfie(),
      );
      expect(blocked.status, LiveSelfieStatus.eyeCovering);
      expect(blocked.done['lookRight'], isFalse);
    });

    test('blink is ignored while a cap is on', () {
      final session = LivenessChallengeSession(
        faceHold: Duration.zero,
        turnHold: Duration.zero,
      );
      final t0 = DateTime.utc(2026, 9, 8);
      _tick(session, now: t0, yaw: 0);
      _tick(session, now: t0, yaw: -22, faces: const [_turnedRight]);
      _tick(session, now: t0, yaw: 22, faces: const [_turnedLeft]);
      expect(session.step, LivenessChallengeStep.blink);

      final blocked = _tick(
        session,
        now: t0.add(const Duration(milliseconds: 100)),
        yaw: 0,
        luma: _cappedSelfie(),
        eyesOpen: false,
        eyesClosed: true,
      );
      expect(blocked.status, LiveSelfieStatus.headCovering);
      expect(blocked.done['blink'], isFalse);
    });
  });
}
