import 'package:flutter_test/flutter_test.dart';
import 'package:thriftline/features/seller/domain/id_image_quality.dart';

void main() {
  group('LiveCaptureStability', () {
    final aligned = LiveIdAssessment(
      status: LiveIdStatus.aligned,
      occupancy: 0.72,
    );
    final searching = const LiveIdAssessment.searching();

    test('does not capture on the first valid frame', () {
      final gate = LiveCaptureStability(
        hold: const Duration(milliseconds: 1000),
      );
      final t0 = DateTime.utc(2026, 1, 1);
      expect(gate.observe(aligned, t0), isFalse);
      expect(
        gate.observe(aligned, t0.add(const Duration(milliseconds: 400))),
        isFalse,
      );
    });

    test('captures after the ID stays valid and still for the hold', () {
      final gate = LiveCaptureStability(
        hold: const Duration(milliseconds: 1000),
      );
      final t0 = DateTime.utc(2026, 1, 1);
      expect(gate.observe(aligned, t0), isFalse);
      expect(
        gate.observe(aligned, t0.add(const Duration(milliseconds: 1000))),
        isTrue,
      );
    });

    test('resets when the ID leaves the frame', () {
      final gate = LiveCaptureStability(
        hold: const Duration(milliseconds: 800),
      );
      final t0 = DateTime.utc(2026, 1, 1);
      gate.observe(aligned, t0);
      expect(
        gate.observe(searching, t0.add(const Duration(milliseconds: 500))),
        isFalse,
      );
      expect(
        gate.observe(aligned, t0.add(const Duration(milliseconds: 501))),
        isFalse,
      );
    });

    test('resets when occupancy jumps, treating the ID as still moving', () {
      final gate = LiveCaptureStability(
        hold: const Duration(milliseconds: 800),
        motionDelta: 0.08,
      );
      final t0 = DateTime.utc(2026, 1, 1);
      gate.observe(aligned, t0);
      final moved = LiveIdAssessment(
        status: LiveIdStatus.aligned,
        occupancy: 0.90,
      );
      expect(
        gate.observe(moved, t0.add(const Duration(milliseconds: 800))),
        isFalse,
      );
    });
  });

  group('LiveIdAssessment copy', () {
    test('avoids internal metric names', () {
      expect(
        const LiveIdAssessment(
          status: LiveIdStatus.poorlyFramed,
        ).feedbackMessage,
        'Align the edges of your ID within the frame',
      );
      expect(
        const LiveIdAssessment(status: LiveIdStatus.blurry).feedbackMessage,
        'Make sure the ID is clear and not blurry.',
      );
      expect(
        const LiveIdAssessment(status: LiveIdStatus.aligned).feedbackMessage,
        contains('ID detected'),
      );
      expect(
        const LiveIdAssessment(status: LiveIdStatus.wrongSide).feedbackMessage,
        contains('Wrong side'),
      );
      expect(
        const LiveIdAssessment(status: LiveIdStatus.notId).feedbackMessage,
        contains('place your ID inside the frame'),
      );
    });
  });
}
