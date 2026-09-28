import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../domain/id_image_quality.dart';
import 'id_bitmap_luma.dart';

/// Crops a captured camera still to the ID-1 guide (and the card, when it is
/// a landscape rectangle). Review and upload should never be the full portrait.
class IdPhotoCropper {
  static const int maxDecodeWidth = 1920;

  static Future<Uint8List> cropToId(
    Uint8List bytes, {
    double cardAspect = IdCaptureGuide.cardAspect,
  }) async {
    if (bytes.isEmpty) return bytes;
    try {
      final codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: maxDecodeWidth,
        allowUpscaling: false,
      );
      final frame = await codec.getNextFrame();
      final image = frame.image;
      try {
        final luma = await _lumaOf(image);
        if (luma == null) return bytes;

        final overlay = IdImageMetrics.centerCardWindow(
          image.width,
          image.height,
          aspect: cardAspect,
        );
        final crop = IdImageMetrics.extractWindow(
          luma,
          image.width,
          image.height,
          overlay,
        );
        var sum = 0;
        for (final v in crop.luma) {
          sum += v;
        }
        final mean = crop.luma.isEmpty ? 0.0 : sum / crop.luma.length;
        final geometry = IdImageMetrics.measureGeometry(
          crop.luma,
          crop.width,
          crop.height,
          mean,
        );
        final window = IdImageMetrics.captureCropWindow(
          imageWidth: image.width,
          imageHeight: image.height,
          overlayGeometry: geometry,
          aspect: cardAspect,
        );
        return await _encodePng(image, window) ?? bytes;
      } finally {
        image.dispose();
      }
    } catch (_) {
      return bytes;
    }
  }

  /// PNG of [bytes] turned clockwise [quarterTurns] times. Null on failure.
  static Future<Uint8List?> rotateClockwise(
    Uint8List bytes,
    int quarterTurns,
  ) async {
    final turns = quarterTurns % 4;
    if (turns == 0) return bytes;
    if (bytes.isEmpty) return null;
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final image = frame.image;
      try {
        final w = image.width.toDouble();
        final h = image.height.toDouble();
        final outW = turns.isOdd ? h : w;
        final outH = turns.isOdd ? w : h;
        final recorder = ui.PictureRecorder();
        final canvas = ui.Canvas(recorder);
        switch (turns) {
          case 1:
            canvas.translate(outW, 0);
          case 2:
            canvas.translate(outW, outH);
          case 3:
            canvas.translate(0, outH);
        }
        canvas.rotate(turns * math.pi / 2);
        canvas.drawImage(image, ui.Offset.zero, ui.Paint());
        final picture = recorder.endRecording();
        final rotated = await picture.toImage(outW.round(), outH.round());
        picture.dispose();
        final png = await rotated.toByteData(format: ui.ImageByteFormat.png);
        rotated.dispose();
        if (png == null) return null;
        return Uint8List.fromList(
          png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes),
        );
      } finally {
        image.dispose();
      }
    } catch (_) {
      return null;
    }
  }

  static Future<List<int>?> _lumaOf(ui.Image image) async {
    var data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    data ??= await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
    if (data == null) return null;
    return IdBitmapLuma.fromRgba(data, image.width, image.height);
  }

  static Future<Uint8List?> _encodePng(
    ui.Image image,
    IdCardWindow window,
  ) async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawImageRect(
      image,
      ui.Rect.fromLTWH(
        window.x0.toDouble(),
        window.y0.toDouble(),
        window.width.toDouble(),
        window.height.toDouble(),
      ),
      ui.Rect.fromLTWH(0, 0, window.width.toDouble(), window.height.toDouble()),
      ui.Paint(),
    );
    final picture = recorder.endRecording();
    final cropped = await picture.toImage(window.width, window.height);
    picture.dispose();
    final png = await cropped.toByteData(format: ui.ImageByteFormat.png);
    cropped.dispose();
    if (png == null) return null;
    return Uint8List.fromList(
      png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes),
    );
  }
}
