import 'package:camera/camera.dart';

import '../domain/id_image_quality.dart';

/// Converts a live [CameraImage] into downsampled luma for frame alignment.
class IdPreviewLuma {
  static const int maxWidth = 320;

  static ({List<int> luma, int width, int height})? sample(CameraImage image) {
    if (image.width < 8 || image.height < 8 || image.planes.isEmpty) {
      return null;
    }
    final plane = image.planes.first;
    final bytes = plane.bytes;
    final stride = plane.bytesPerRow;
    if (bytes.isEmpty || stride < 1) return null;

    final bpp = plane.bytesPerPixel ?? 1;
    final luma = bpp >= 4
        ? IdImageMetrics.lumaFromBgra(
            bytes: bytes,
            width: image.width,
            height: image.height,
            bytesPerRow: stride,
          )
        : IdImageMetrics.copyYPlane(
            bytes: bytes,
            width: image.width,
            height: image.height,
            bytesPerRow: stride,
          );
    if (luma.length < 64) return null;
    return IdImageMetrics.downsample(
      luma,
      image.width,
      image.height,
      maxWidth: maxWidth,
    );
  }
}
