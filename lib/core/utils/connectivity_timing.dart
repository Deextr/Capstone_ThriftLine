import 'package:flutter/foundation.dart';

/// Measures asynchronous activity latency for connectivity checks.
///
/// Output is intentionally limited to debug builds so response-time
/// diagnostics never appear in a release build or in the user-facing UI.
class ConnectivityTiming {
  ConnectivityTiming._();

  static Stopwatch start(String activity) {
    final stopwatch = Stopwatch()..start();
    if (kDebugMode) {
      debugPrint('[Connectivity] $activity started');
    }
    return stopwatch;
  }

  static void finish(String activity, Stopwatch stopwatch) {
    stopwatch.stop();
    if (kDebugMode) {
      debugPrint(
        '[Connectivity] $activity: ${stopwatch.elapsedMilliseconds} ms',
      );
    }
  }

  static Future<T> measure<T>(
    String activity,
    Future<T> Function() operation,
  ) async {
    final stopwatch = start(activity);
    try {
      return await operation();
    } finally {
      finish(activity, stopwatch);
    }
  }

  static T measureSync<T>(String activity, T Function() operation) {
    final stopwatch = start(activity);
    try {
      return operation();
    } finally {
      finish(activity, stopwatch);
    }
  }
}
