// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

/// The kinds of automated tests tracked by the QA suite.
enum QaTestType {
  unit('UNIT TEST', 'Individual functions/classes', 'flutter_test'),
  widget('WIDGET TEST', 'Individual screens/widgets', 'flutter_test'),
  integration(
    'INTEGRATION TEST',
    'End-to-end integration flows',
    'integration_test',
  );

  const QaTestType(this.label, this.scope, this.framework);

  final String label;
  final String scope;
  final String framework;
}

class _QaTally {
  int passed = 0;
  final List<String> failed = [];

  int get total => passed + failed.length;
  bool get ran => total > 0;
  bool get allPassed => failed.isEmpty;
}

/// Collects per-test results and prints a readable status log.
///
/// Every test prints one line when it finishes:
///   `✅ Validators › email › accepts a valid address passed`
/// and every test type prints a summary line when its group completes:
///   `UNIT TEST ✅ PASSED (110/110)`
///   `INTEGRATION TEST ✅ PASSED (5/5)`
abstract final class QaReporter {
  static final Map<QaTestType, _QaTally> _tallies = {
    for (final type in QaTestType.values) type: _QaTally(),
  };

  /// Group names active while tests are being *declared* (synchronous).
  static final List<String> _groupStack = [];

  static const _line =
      '══════════════════════════════════════════════════════════════';

  static String qualify(String description) =>
      [..._groupStack, description].join(' › ');

  static void pass(QaTestType type, String name) {
    _tallies[type]!.passed++;
    print('  ✅ $name passed');
  }

  static void fail(QaTestType type, String name, Object error) {
    _tallies[type]!.failed.add(name);
    final reason = '$error'.trim().split('\n').first;
    print('  ❌ $name FAILED → $reason');
  }

  static void printTypeHeader(QaTestType type) {
    print('');
    print(_line);
    print('  ▶ ${type.label}S  ·  ${type.scope}  ·  ${type.framework}');
    print(_line);
  }

  static void printTypeSummary(QaTestType type) {
    final tally = _tallies[type]!;
    print('──────────────────────────────────────────────────────────────');
    print('  ${_statusLine(type.label, tally.passed, tally.total)}');
    for (final name in tally.failed) {
      print('     ↳ failed: $name');
    }
  }

  static void printFinalReport() {
    final ran = QaTestType.values.where((t) => _tallies[t]!.ran).toList();
    if (ran.isEmpty) return;

    var passed = 0;
    var total = 0;
    print('');
    print(_line);
    print('  THRIFTLINE QA TEST STATUS');
    print(_line);
    for (final type in ran) {
      final tally = _tallies[type]!;
      passed += tally.passed;
      total += tally.total;
      print('  ${_statusLine(type.label, tally.passed, tally.total)}');
    }
    print('  ${_statusLine('OVERALL', passed, total)}');
    print(_line);
  }

  static String _statusLine(String label, int passed, int total) {
    final ok = passed == total;
    final status = ok ? '✅ PASSED' : '❌ FAILED';
    return '${label.padRight(16)} $status ($passed/$total)';
  }
}

/// Declares one test-type section (UNIT / WIDGET / INTEGRATION) with its own
/// header and summary.
void qaSection(QaTestType type, void Function() body) {
  group('[${type.label}]', () {
    setUpAll(() {
      GoogleFonts.config.allowRuntimeFetching = false;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (MethodCall methodCall) async => Directory.systemTemp.path,
      );
      final originalOnError = FlutterError.onError;
      FlutterError.onError = (FlutterErrorDetails details) {
        final text = details.exception.toString();
        if (text.contains('Failed to load font') ||
            text.contains('google_fonts was unable to load font')) {
          return;
        }
        originalOnError?.call(details);
      };
      PlatformDispatcher.instance.onError = (error, stack) {
        final text = error.toString();
        if (text.contains('Failed to load font') ||
            text.contains('google_fonts was unable to load font')) {
          return true;
        }
        return false;
      };
      QaReporter.printTypeHeader(type);
    });
    tearDownAll(() => QaReporter.printTypeSummary(type));
    body();
  });
}

/// A named group whose name is included in each printed test status.
void qaGroup(String name, void Function() body) {
  group(name, () {
    QaReporter._groupStack.add(name);
    try {
      body();
    } finally {
      QaReporter._groupStack.removeLast();
    }
  });
}

/// A unit test (pure functions/classes) that reports its status.
void qaUnitTest(String description, FutureOr<void> Function() body) {
  final name = QaReporter.qualify(description);
  test(description, () async {
    try {
      await body();
    } catch (error) {
      QaReporter.fail(QaTestType.unit, name, error);
      rethrow;
    }
    QaReporter.pass(QaTestType.unit, name);
  });
}

/// A widget test (individual screens/widgets) that reports its status.
void qaWidgetTest(
  String description,
  Future<void> Function(WidgetTester tester) body,
) {
  final name = QaReporter.qualify(description);
  testWidgets(description, (tester) async {
    final prevOnError = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {
      final text = details.exception.toString();
      if (text.contains('Failed to load font') ||
          text.contains('google_fonts was unable to load font')) {
        return;
      }
      prevOnError?.call(details);
    };
    addTearDown(() => FlutterError.onError = prevOnError);

    try {
      await body(tester);
      final pending = tester.takeException();
      if (pending != null &&
          !pending.toString().contains('Failed to load font') &&
          !pending.toString().contains('google_fonts was unable to load font')) {
        throw pending;
      }
    } catch (error) {
      QaReporter.fail(QaTestType.widget, name, error);
      rethrow;
    }
    QaReporter.pass(QaTestType.widget, name);
  });
}

/// An integration test (end-to-end flow) that reports its status.
void qaIntegrationTest(
  String description,
  Future<void> Function(WidgetTester tester) body,
) {
  final name = QaReporter.qualify(description);
  testWidgets(description, (tester) async {
    final prevOnError = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {
      final text = details.exception.toString();
      if (text.contains('Failed to load font') ||
          text.contains('google_fonts was unable to load font')) {
        return;
      }
      prevOnError?.call(details);
    };
    addTearDown(() => FlutterError.onError = prevOnError);

    try {
      await body(tester);
      final pending = tester.takeException();
      if (pending != null &&
          !pending.toString().contains('Failed to load font') &&
          !pending.toString().contains('google_fonts was unable to load font')) {
        throw pending;
      }
    } catch (error) {
      QaReporter.fail(QaTestType.integration, name, error);
      rethrow;
    }
    QaReporter.pass(QaTestType.integration, name);
  });
}
