import 'package:flutter_test/flutter_test.dart';
import 'package:thriftline/features/seller/data/id_preview_luma.dart';
import 'package:thriftline/features/seller/domain/id_image_quality.dart';

void main() {
  test('90° rotation matches CameraPreview axis swap', () {
    const width = 3;
    const height = 2;
    final luma = <int>[1, 2, 3, 4, 5, 6];
    final rotated = IdPreviewLuma.rotateClockwise(luma, width, height, 90);
    expect(rotated.width, 2);
    expect(rotated.height, 3);
    expect(rotated.luma, [4, 1, 5, 2, 6, 3]);
  });

  test('the ID-1 guide is landscape after a 90° sensor rotation', () {
    const sensorW = 160;
    const sensorH = 90;
    final rotated = IdPreviewLuma.rotateClockwise(
      List<int>.filled(sensorW * sensorH, 200),
      sensorW,
      sensorH,
      90,
    );
    expect(rotated.width, sensorH);
    expect(rotated.height, sensorW);
    final hole = IdImageMetrics.centerCardWindow(rotated.width, rotated.height);
    expect(hole.width / hole.height, closeTo(IdCaptureGuide.cardAspect, 0.08));
    expect(hole.width > hole.height, isTrue);
  });
}
