import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';

import '../domain/id_image_quality.dart';

/// Converts a live [CameraImage] into downsampled luma for frame alignment.
///
/// Call this before awaiting work in the image-stream callback.
/// [CameraImage] plane buffers are recycled after that callback yields.
class IdPreviewLuma {
  static const int maxWidth = 320;

  static ({List<int> luma, int width, int height})? sample(
    CameraImage image, {
    int rotationDegrees = 0,
  }) {
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
    final sampled = IdImageMetrics.downsample(
      luma,
      image.width,
      image.height,
      maxWidth: maxWidth,
    );
    // CameraPreview is shown upright (portrait SizedBox with swapped sides).
    // The Y plane is still sensor-native. Rotate before the ID-1 guide so
    // alignment looks at the same hole the user is filling.
    return rotateClockwise(
      sampled.luma,
      sampled.width,
      sampled.height,
      rotationDegrees,
    );
  }

  /// Clockwise rotation of a packed luma buffer. Used so live detection
  /// matches [CameraPreview] after [CameraDescription.sensorOrientation].
  @visibleForTesting
  static ({List<int> luma, int width, int height}) rotateClockwise(
    List<int> luma,
    int width,
    int height,
    int degrees,
  ) {
    final turn = ((degrees % 360) + 360) % 360;
    if (turn == 0 || width < 1 || height < 1 || luma.length < width * height) {
      return (luma: luma, width: width, height: height);
    }
    if (turn == 180) {
      final out = List<int>.filled(width * height, 0);
      for (var y = 0; y < height; y++) {
        for (var x = 0; x < width; x++) {
          out[(height - 1 - y) * width + (width - 1 - x)] = luma[y * width + x];
        }
      }
      return (luma: out, width: width, height: height);
    }
    if (turn == 90 || turn == 270) {
      final newWidth = height;
      final newHeight = width;
      final out = List<int>.filled(newWidth * newHeight, 0);
      for (var y = 0; y < height; y++) {
        for (var x = 0; x < width; x++) {
          final nx = turn == 90 ? height - 1 - y : y;
          final ny = turn == 90 ? x : width - 1 - x;
          out[ny * newWidth + nx] = luma[y * width + x];
        }
      }
      return (luma: out, width: newWidth, height: newHeight);
    }
    return (luma: luma, width: width, height: height);
  }
}
