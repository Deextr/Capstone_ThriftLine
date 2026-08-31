import 'package:flutter/foundation.dart';

/// Outcome of the Become a Seller face check.
///
/// [passed] requires the live challenge **and** an independent quality pass
/// on the final captured image. Live challenge flags alone are not enough.
class LivenessResult {
  const LivenessResult({
    required this.imageBytes,
    required this.fileName,
    required this.challenges,
    required this.imageQualityPassed,
  });

  final Uint8List imageBytes;
  final String fileName;
  final Map<String, bool> challenges;

  /// Result of face detection + quality on the captured JPEG, not the stream.
  final bool imageQualityPassed;

  bool get livenessPassed =>
      challenges['face'] == true &&
      challenges['blink'] == true &&
      challenges['lookLeft'] == true &&
      challenges['lookRight'] == true;

  bool get passed => livenessPassed && imageQualityPassed;
}
