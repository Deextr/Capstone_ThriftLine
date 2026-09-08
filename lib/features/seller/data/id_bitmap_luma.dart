import 'dart:typed_data';
import 'dart:ui' as ui;

/// Decodes a captured still to luminance without lying about native size.
///
/// [ui.instantiateImageCodec] with only `targetWidth` yields the *scaled*
/// bitmap. Using those dimensions for the "too small" check flags a normal
/// landscape ID-1 crop (short side ~450px after a 720px downsample). Pixel
/// buffers can also include row padding; a packed `i * 4` walk then throws
/// and was previously mapped to the same "resolution too low" error.
class IdBitmapLuma {
  static const int analyzeMaxWidth = 720;

  static List<int>? fromRgba(ByteData data, int width, int height) {
    if (width < 1 || height < 1) return null;
    final bytes = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    if (bytes.length < 4) return null;

    final packedRow = width * 4;
    if (bytes.length >= height * packedRow) {
      final rowStride = bytes.length ~/ height;
      if (rowStride < packedRow) return null;
      return _lumaFromRows(bytes, width, height, rowStride, 4);
    }

    // Some backends report RGB (no alpha) with a tight or padded stride.
    if (bytes.length >= height * width * 3) {
      final rowStride = bytes.length ~/ height;
      if (rowStride >= width * 3) {
        return _lumaFromRows(bytes, width, height, rowStride, 3);
      }
    }
    return null;
  }

  static List<int>? _lumaFromRows(
    Uint8List bytes,
    int width,
    int height,
    int rowStride,
    int bpp,
  ) {
    final luma = List<int>.filled(width * height, 0);
    for (var y = 0; y < height; y++) {
      final row = y * rowStride;
      for (var x = 0; x < width; x++) {
        final o = row + x * bpp;
        if (o + 2 >= bytes.length) return luma;
        luma[y * width + x] =
            ((0.299 * bytes[o]) +
                    (0.587 * bytes[o + 1]) +
                    (0.114 * bytes[o + 2]))
                .round();
      }
    }
    return luma;
  }

  static Future<DecodedIdBitmap?> decode(
    Uint8List bytes, {
    int maxWidth = analyzeMaxWidth,
  }) async {
    if (bytes.isEmpty) return null;
    final fromDescriptor = await _decodeWithDescriptor(bytes, maxWidth);
    if (fromDescriptor != null) return fromDescriptor;
    return _decodeWithCodec(bytes, maxWidth);
  }

  static Future<DecodedIdBitmap?> _decodeWithDescriptor(
    Uint8List bytes,
    int maxWidth,
  ) async {
    ui.ImmutableBuffer? buffer;
    ui.ImageDescriptor? descriptor;
    ui.Image? image;
    try {
      buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      final nativeWidth = descriptor.width;
      final nativeHeight = descriptor.height;
      if (nativeWidth < 1 || nativeHeight < 1) return null;

      final codec = await descriptor.instantiateCodec(
        targetWidth: nativeWidth > maxWidth ? maxWidth : nativeWidth,
      );
      final frame = await codec.getNextFrame();
      image = frame.image;
      final luma = await _lumaOf(image);
      if (luma == null) {
        image.dispose();
        return null;
      }
      return DecodedIdBitmap(
        luma: luma,
        width: image.width,
        height: image.height,
        nativeWidth: nativeWidth,
        nativeHeight: nativeHeight,
        image: image,
      );
    } catch (_) {
      image?.dispose();
      return null;
    } finally {
      descriptor?.dispose();
      buffer?.dispose();
    }
  }

  static Future<DecodedIdBitmap?> _decodeWithCodec(
    Uint8List bytes,
    int maxWidth,
  ) async {
    ui.Image? image;
    try {
      final nativeCodec = await ui.instantiateImageCodec(
        bytes,
        allowUpscaling: false,
      );
      final nativeFrame = await nativeCodec.getNextFrame();
      final nativeWidth = nativeFrame.image.width;
      final nativeHeight = nativeFrame.image.height;
      if (nativeWidth < 1 || nativeHeight < 1) {
        nativeFrame.image.dispose();
        return null;
      }

      if (nativeWidth <= maxWidth) {
        image = nativeFrame.image;
      } else {
        nativeFrame.image.dispose();
        final scaled = await ui.instantiateImageCodec(
          bytes,
          targetWidth: maxWidth,
          allowUpscaling: false,
        );
        image = (await scaled.getNextFrame()).image;
      }

      final luma = await _lumaOf(image);
      if (luma == null) {
        image.dispose();
        return null;
      }
      return DecodedIdBitmap(
        luma: luma,
        width: image.width,
        height: image.height,
        nativeWidth: nativeWidth,
        nativeHeight: nativeHeight,
        image: image,
      );
    } catch (_) {
      image?.dispose();
      return null;
    }
  }

  static Future<List<int>?> _lumaOf(ui.Image image) async {
    var data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    data ??= await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
    if (data == null) return null;
    return fromRgba(data, image.width, image.height);
  }
}

class DecodedIdBitmap {
  const DecodedIdBitmap({
    required this.luma,
    required this.width,
    required this.height,
    required this.nativeWidth,
    required this.nativeHeight,
    required this.image,
  });

  final List<int> luma;
  final int width;
  final int height;
  final int nativeWidth;
  final int nativeHeight;
  final ui.Image image;
}
