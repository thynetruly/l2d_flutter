import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

/// Utilities for comparing Dart output against C++ golden reference data.
class GoldenComparator {
  GoldenComparator._();

  /// Loads a golden JSON file and returns the parsed map.
  static Map<String, dynamic> loadGolden(String relativePath) {
    final path = '${Directory.current.path}/test/golden/$relativePath';
    final file = File(path);
    if (!file.existsSync()) {
      fail('Golden file not found: $path');
    }
    return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  }

  /// Compares a list of actual values against golden values within [epsilon].
  static void compareValues({
    required List<Map<String, dynamic>> goldenEntries,
    required List<double> actualValues,
    required String valueKey,
    double epsilon = 1e-6,
    String? label,
  }) {
    expect(actualValues.length, equals(goldenEntries.length),
        reason: '${label ?? "Values"} count mismatch');

    for (int i = 0; i < goldenEntries.length; i++) {
      final expected = (goldenEntries[i][valueKey] as num).toDouble();
      final actual = actualValues[i];
      expect(actual, closeTo(expected, epsilon),
          reason:
              '${label ?? "Value"} mismatch at index $i: expected $expected, got $actual');
    }
  }

  /// Compares frame-by-frame parameter values against golden data.
  static void compareParameterFrames({
    required List<Map<String, dynamic>> goldenFrames,
    required List<Map<String, double>> actualFrames,
    double epsilon = 1e-5,
    String? label,
  }) {
    expect(actualFrames.length, equals(goldenFrames.length),
        reason: '${label ?? "Frames"} count mismatch');

    for (int i = 0; i < goldenFrames.length; i++) {
      final goldenParams =
          goldenFrames[i]['params'] as Map<String, dynamic>? ?? {};
      final actualParams = actualFrames[i];

      for (final entry in goldenParams.entries) {
        final expected = (entry.value as num).toDouble();
        final actual = actualParams[entry.key];
        expect(actual, isNotNull,
            reason:
                'Frame $i: parameter "${entry.key}" missing in actual output');
        expect(actual, closeTo(expected, epsilon),
            reason:
                'Frame $i, param "${entry.key}": expected $expected, got $actual');
      }
    }
  }

  /// Compares a flat list of floats (e.g., matrix values) against golden.
  static void compareFloatList({
    required List<dynamic> golden,
    required List<double> actual,
    double epsilon = 1e-6,
    String? label,
  }) {
    expect(actual.length, equals(golden.length),
        reason: '${label ?? "Array"} length mismatch');

    for (int i = 0; i < golden.length; i++) {
      final expected = (golden[i] as num).toDouble();
      expect(actual[i], closeTo(expected, epsilon),
          reason:
              '${label ?? "Element"} [$i]: expected $expected, got ${actual[i]}');
    }
  }
}
