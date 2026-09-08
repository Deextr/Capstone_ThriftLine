import 'dart:io';
import 'dart:ui' show Size;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// Builds an [InputImage] from a camera frame with copied bytes.
///
/// [CameraImage] plane buffers are recycled after the stream callback returns.
class IdCameraInputImage {
  static InputImage? fromCamera(CameraImage image, CameraDescription camera) {
    try {
      if (image.planes.isEmpty || image.width < 8 || image.height < 8) {
        return null;
      }

      final rotation =
          InputImageRotationValue.fromRawValue(camera.sensorOrientation) ??
          InputImageRotation.rotation0deg;

      late final Uint8List payload;
      late final int rowStride;
      late final InputImageFormat format;

      if (Platform.isIOS) {
        payload = _copiedBytes(image);
        if (payload.isEmpty) return null;
        rowStride = image.planes.first.bytesPerRow;
        format = InputImageFormat.bgra8888;
      } else if (Platform.isAndroid) {
        final nv21 = androidNv21(image);
        if (nv21 == null || nv21.bytes.isEmpty) return null;
        payload = nv21.bytes;
        rowStride = nv21.bytesPerRow;
        format = InputImageFormat.nv21;
      } else {
        payload = _copiedBytes(image);
        if (payload.isEmpty) return null;
        rowStride = image.planes.first.bytesPerRow;
        final detected = InputImageFormatValue.fromRawValue(image.format.raw);
        if (detected == null) return null;
        format = detected;
      }

      return InputImage.fromBytes(
        bytes: payload,
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: rotation,
          format: format,
          bytesPerRow: rowStride,
        ),
      );
    } catch (_) {
      return null;
    }
  }

  static Uint8List _copiedBytes(CameraImage image) {
    if (image.planes.length == 1) {
      return Uint8List.fromList(image.planes.first.bytes);
    }
    final write = WriteBuffer();
    for (final plane in image.planes) {
      write.putUint8List(Uint8List.fromList(plane.bytes));
    }
    return write.done().buffer.asUint8List();
  }

  /// Android ML Kit only accepts NV21. Many devices still deliver YUV_420_888.
  @visibleForTesting
  static ({Uint8List bytes, int bytesPerRow})? androidNv21(CameraImage image) {
    if (image.planes.length == 1) {
      return (
        bytes: Uint8List.fromList(image.planes.first.bytes),
        bytesPerRow: image.planes.first.bytesPerRow,
      );
    }
    if (image.planes.length < 3) return null;
    final packed = nv21FromYuv420(
      width: image.width,
      height: image.height,
      y: image.planes[0].bytes,
      yRowStride: image.planes[0].bytesPerRow,
      u: image.planes[1].bytes,
      v: image.planes[2].bytes,
      uvRowStride: image.planes[1].bytesPerRow,
      uvPixelStride: image.planes[1].bytesPerPixel ?? 1,
    );
    if (packed == null) return null;
    return (bytes: packed, bytesPerRow: image.width);
  }

  @visibleForTesting
  static Uint8List? nv21FromYuv420({
    required int width,
    required int height,
    required List<int> y,
    required int yRowStride,
    required List<int> u,
    required List<int> v,
    required int uvRowStride,
    required int uvPixelStride,
  }) {
    if (width < 2 || height < 2 || yRowStride < width) return null;
    if (uvRowStride < 1 || uvPixelStride < 1) return null;

    final nv21 = Uint8List(width * height * 3 ~/ 2);
    var dst = 0;
    for (var row = 0; row < height; row++) {
      final src = row * yRowStride;
      if (src + width > y.length) return null;
      nv21.setRange(dst, dst + width, y, src);
      dst += width;
    }

    final uvHeight = height ~/ 2;
    final uvWidth = width ~/ 2;
    for (var row = 0; row < uvHeight; row++) {
      for (var col = 0; col < uvWidth; col++) {
        final uvIndex = row * uvRowStride + col * uvPixelStride;
        if (uvIndex >= u.length || uvIndex >= v.length) return null;
        nv21[dst++] = v[uvIndex];
        nv21[dst++] = u[uvIndex];
      }
    }
    return nv21;
  }
}
