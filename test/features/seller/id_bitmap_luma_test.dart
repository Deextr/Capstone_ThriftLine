import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:thriftline/features/seller/data/id_bitmap_luma.dart';
import 'package:thriftline/features/seller/data/id_image_quality_analyzer.dart';
import 'package:thriftline/features/seller/domain/id_image_quality.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('IdBitmapLuma', () {
    test('reads tightly packed RGBA', () {
      final pixels = Uint8List.fromList([
        255,
        255,
        255,
        255,
        0,
        0,
        0,
        255,
        255,
        255,
        255,
        255,
        0,
        0,
        0,
        255,
      ]);
      final luma = IdBitmapLuma.fromRgba(ByteData.sublistView(pixels), 2, 2);
      expect(luma, isNotNull);
      expect(luma, [255, 0, 255, 0]);
    });

    test('reads row-padded RGBA without throwing', () {
      const width = 2;
      const height = 2;
      const stride = 16; // padded from 8
      final pixels = Uint8List(stride * height);
      void put(int x, int y, int r, int g, int b) {
        final o = y * stride + x * 4;
        pixels[o] = r;
        pixels[o + 1] = g;
        pixels[o + 2] = b;
        pixels[o + 3] = 255;
      }

      put(0, 0, 255, 255, 255);
      put(1, 0, 0, 0, 0);
      put(0, 1, 255, 255, 255);
      put(1, 1, 0, 0, 0);

      final luma = IdBitmapLuma.fromRgba(
        ByteData.sublistView(pixels),
        width,
        height,
      );
      expect(luma, isNotNull);
      expect(luma, [255, 0, 255, 0]);
    });

    test('short buffers return null instead of throwing', () {
      expect(IdBitmapLuma.fromRgba(ByteData(6), 80, 50), isNull);
    });
  });

  group('IdImageQualityAnalyzer', () {
    test('a cropped ID-1 PNG is not flagged as too small', () async {
      const width = 800;
      const height = 504;
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      canvas.drawRect(
        ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
        ui.Paint()..color = const ui.Color(0xFFD2D2D2),
      );
      canvas.drawRect(
        const ui.Rect.fromLTWH(8, 8, 784, 488),
        ui.Paint()..color = const ui.Color(0xFFE8E8E8),
      );
      canvas.drawRect(
        const ui.Rect.fromLTWH(24, 40, 160, 220),
        ui.Paint()..color = const ui.Color(0xFF6E6E6E),
      );
      final line = ui.Paint()
        ..color = const ui.Color(0xFF1E1E1E)
        ..strokeWidth = 3;
      for (final y in [48.0, 96.0, 144.0, 192.0, 240.0, 288.0, 336.0]) {
        canvas.drawLine(ui.Offset(210, y), ui.Offset(760, y), line);
      }
      final picture = recorder.endRecording();
      final image = await picture.toImage(width, height);
      picture.dispose();
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      expect(png, isNotNull);

      final bytes = Uint8List.fromList(
        png!.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes),
      );
      final result = await IdImageQualityAnalyzer().analyze(bytes);

      expect(
        result.issue,
        isNot(IdQualityIssue.tooSmall),
        reason: result.debug ?? result.message,
      );
      expect(
        result.issue,
        isNot(IdQualityIssue.missing),
        reason: result.debug ?? result.message,
      );
    });
  });
}
