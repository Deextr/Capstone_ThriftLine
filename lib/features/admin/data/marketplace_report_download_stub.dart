import 'dart:typed_data';

void downloadReportBytes({
  required Uint8List bytes,
  required String fileName,
  required String mimeType,
}) {
  throw UnsupportedError('Report download is only supported on web.');
}
