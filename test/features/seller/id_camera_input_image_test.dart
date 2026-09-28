import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:thriftline/features/seller/data/id_camera_input_image.dart';

void main() {
  test('packs YUV_420_888 with padding into NV21 VU order', () {
    const width = 4;
    const height = 2;
    final y = Uint8List.fromList([10, 11, 12, 13, 99, 20, 21, 22, 23, 99]);
    final u = Uint8List.fromList([1, 80, 2, 80]);
    final v = Uint8List.fromList([3, 80, 4, 80]);

    final nv21 = IdCameraInputImage.nv21FromYuv420(
      width: width,
      height: height,
      y: y,
      yRowStride: 5,
      u: u,
      v: v,
      uvRowStride: 4,
      uvPixelStride: 2,
    );

    expect(nv21, isNotNull);
    expect(nv21!.sublist(0, 8), [10, 11, 12, 13, 20, 21, 22, 23]);
    expect(nv21.sublist(8), [3, 1, 4, 2]);
  });

  test('rejects a truncated Y plane instead of packing garbage', () {
    final nv21 = IdCameraInputImage.nv21FromYuv420(
      width: 4,
      height: 2,
      y: Uint8List.fromList([1, 2, 3]),
      yRowStride: 4,
      u: Uint8List.fromList([1, 2]),
      v: Uint8List.fromList([3, 4]),
      uvRowStride: 2,
      uvPixelStride: 1,
    );
    expect(nv21, isNull);
  });
}
